import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

const BAND = {
  plugin: 'session-focus',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isWorking: false,
    maxRows: 10,
    bodyColumns: 100,
    scroll: { offset: 0, bodyRows: 10 },
    view: {},
  },
} as const

const USAGE = { input_tokens: 1, output_tokens: 1, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 }

function engine(on: On, env: Record<string, string> = {}) {
  mock.clock(on, { now: 0 })
  mock.env(on, env)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e) => ({ text: e.text }))
  /* Stands for the engine and the plugins beneath, such as pr-band. */
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>beneath</Text>
  })
}

/* The mod summarizes without holding up the prompt, so a test lets that work finish. */
/* The test runtime has timers, but the engine's typings declare none. */
declare function setTimeout(handler: () => void, ms: number): number

function settle() {
  return new Promise<void>(resolve => setTimeout(() => resolve(), 20))
}

function submit(text: string) {
  return { text, wait: false, origin: { kind: 'composer' } } as const
}

test('the band shows the model summary of recent prompts, on every surface', async ($, on) => {
  engine(on)
  const asked: string[] = []
  on('model.complete', (_, e) => {
    asked.push(e.prompt)
    return { value: { isAnswered: true, text: 'Fix Alerts Pane Tests.\n', usage: USAGE } }
  })

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.prompt.submit(submit('the alerts test fails on CI'))
  await settle()

  expect(asked[0]).toContain('the alerts test fails on CI')
  for (const surface of ['terminal', 'desktop', 'vscode', 'mobile'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect((await ui.find({ type: 'Text', text: /Alerts/ }))?.text).toBe('▸ Fix Alerts Pane Tests')
    await ui.unmount()
  }
})

test('slash commands are not summarized', async ($, on) => {
  engine(on)
  let calls = 0
  on('model.complete', () => {
    calls += 1
    return { value: { isAnswered: true, text: 'x', usage: USAGE } }
  })

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.prompt.submit({ ...submit('/clear'), command: { name: 'clear', args: '' } })

  expect(calls).toBe(0)
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /▸/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'beneath' })).toBeDefined()
  await ui.unmount()
})

test('a failed call keeps the last summary and says it failed', async ($, on) => {
  engine(on)
  let fail = false
  on('model.complete', () =>
    fail
      ? { value: { isAnswered: false, reason: 'api-error', status: 529, error: 'overloaded', usage: USAGE } }
      : { value: { isAnswered: true, text: 'Write Session Focus Mod', usage: USAGE } },
  )

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.prompt.submit(submit('build the focus pane'))
  await settle()
  fail = true
  await $.prompt.submit(submit('add tests'))
  await settle()

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: 'Write Session Focus Mod' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /update failed: api-error/ })).toBeDefined()
  await ui.unmount()
})

test('prompts the user did not type are not summarized', async ($, on) => {
  engine(on)
  let calls = 0
  on('model.complete', () => {
    calls += 1
    return { value: { isAnswered: true, text: 'x', usage: USAGE } }
  })

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.prompt.submit({ ...submit('task finished'), origin: { kind: 'task-notification' } })
  await settle()

  expect(calls).toBe(0)
})

test('only the last six prompts reach the model', async ($, on) => {
  engine(on)
  let last = ''
  on('model.complete', (_, e) => {
    last = e.prompt
    return { value: { isAnswered: true, text: 'Many Prompts', usage: USAGE } }
  })

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  for (let i = 1; i <= 8; i += 1) await $.prompt.submit(submit(`prompt number ${i}`))

  expect(last).not.toContain('prompt number 2')
  expect(last).toContain('prompt number 3')
  expect(last).toContain('prompt number 8')
})

test('the summary takes one row above what the plugins beneath draw', async ($, on) => {
  engine(on)
  on('model.complete', () => ({ value: { isAnswered: true, text: 'Compact Focus Band', usage: USAGE } }))

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.prompt.submit(submit('make the focus pane a band'))
  await settle()

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  const band = await ui.drawn()
  const rows = band.type === 'Box' ? (band.children ?? []) : []
  expect(rows).toHaveLength(2)
  expect(await ui.find({ type: 'Text', text: 'Compact Focus Band' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'beneath' })).toBeDefined()
  await ui.unmount()
})

test('a survey hides the band', async ($, on) => {
  engine(on)
  on('model.complete', () => ({ value: { isAnswered: true, text: 'Compact Focus Band', usage: USAGE } }))

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.prompt.submit(submit('make the focus pane a band'))
  await settle()

  const ui = await $.ui.mount({ ...BAND, props: { ...BAND.props, hasSurvey: true }, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: 'Compact Focus Band' })).toBeUndefined()
  await ui.unmount()
})

test('inside herdr, the summary goes to the sidebar as the focus token', async ($, on) => {
  engine(on, { HERDR_PANE_ID: 'w1:p2' })
  on('model.complete', () => ({ value: { isAnswered: true, text: 'Herdr Sidebar Focus', usage: USAGE } }))
  const ran: (readonly string[])[] = []
  on('process.run', (_, e) => {
    ran.push(e.argv)
    return { value: { exitCode: 0, stdout: '', stderr: '' } }
  })

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.prompt.submit(submit('show the focus in the herdr sidebar'))
  await settle()

  const clear = ['herdr', 'pane', 'report-metadata', 'w1:p2', '--source', 'agent-config:session-focus', '--clear-token', 'focus']
  expect(ran).toEqual([
    clear,
    clear,
    ['herdr', 'pane', 'report-metadata', 'w1:p2', '--source', 'agent-config:session-focus', '--token', 'focus=Herdr Sidebar Focus'],
  ])
})

test('each prompt resends the current label to herdr before the new summary', async ($, on) => {
  engine(on, { HERDR_PANE_ID: 'w1:p2' })
  let fail = false
  on('model.complete', () =>
    fail
      ? { value: { isAnswered: false, reason: 'api-error', status: 529, error: 'overloaded', usage: USAGE } }
      : { value: { isAnswered: true, text: 'Kept Label', usage: USAGE } },
  )
  const ran: (readonly string[])[] = []
  on('process.run', (_, e) => {
    ran.push(e.argv)
    return { value: { exitCode: 0, stdout: '', stderr: '' } }
  })

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.prompt.submit(submit('first'))
  await settle()
  fail = true
  ran.length = 0
  await $.prompt.submit(submit('second'))
  await settle()

  expect(ran.map(argv => argv.slice(-2))).toEqual([['--token', 'focus=Kept Label']])
})

test('outside herdr, nothing is reported', async ($, on) => {
  engine(on)
  on('model.complete', () => ({ value: { isAnswered: true, text: 'Plain Terminal', usage: USAGE } }))
  let runs = 0
  on('process.run', () => {
    runs += 1
    return { value: { exitCode: 0, stdout: '', stderr: '' } }
  })

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.prompt.submit(submit('no herdr here'))
  await settle()

  expect(runs).toBe(0)
})

test('a failed herdr report still shows the new label', async ($, on) => {
  engine(on, { HERDR_PANE_ID: 'w1:p2' })
  on('model.complete', () => ({ value: { isAnswered: true, text: 'Herdr Report Fails', usage: USAGE } }))
  on('process.run', () => ({ deny: 'herdr is not on PATH' }))

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.prompt.submit(submit('report while herdr is missing'))
  await settle()

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: 'Herdr Report Fails' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /update failed/ })).toBeUndefined()
  await ui.unmount()
})
