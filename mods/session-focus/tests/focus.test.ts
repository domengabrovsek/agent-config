import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

const PANE = {
  plugin: 'session-focus',
  component: 'Pane',
  requestId: 'session-focus',
  props: {
    title: 'Focus',
    isFocused: false,
    bodyColumns: 40,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 10 },
    view: {},
  },
} as const

const USAGE = { input_tokens: 1, output_tokens: 1, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 }

function engine(on: On) {
  mock.clock(on, { now: 0 })
  on('command.register', () => ({ value: { command: 'session-focus' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e) => ({ text: e.text }))
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

test('the pane shows the model summary of recent prompts, on every surface', async ($, on) => {
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
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /Alerts/ }))?.text).toBe('Fix Alerts Pane Tests')
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
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('No prompts yet.')
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

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: 'Write Session Focus Mod' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /last update failed: api-error/ })).toBeDefined()
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

test('/session-focus opens the pane', async ($, on) => {
  mock.clock(on, { now: 0 })
  on('command.register', () => ({ value: { command: 'session-focus' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  const opened: string[] = []
  on('ui.open', (_, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true } }
  })

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const result = await $.command.run({
    command: 'session-focus',
    args: '',
    origin: { kind: 'composer' },
    presentation: { isFullscreen: true, columns: 160 },
  })

  expect(result).toMatchObject({ text: 'Focus pane opened.' })
  expect(opened).toContain('session-focus')
})
