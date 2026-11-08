import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

const BAND = {
  plugin: 'pr-band',
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

function prJson(overrides: Record<string, string | boolean | object[]> = {}): string {
  return JSON.stringify({
    number: 223,
    url: 'https://github.com/owner/repo/pull/223',
    state: 'OPEN',
    isDraft: false,
    title: 'feat(mods): add a pane',
    reviewDecision: '',
    mergeable: 'MERGEABLE',
    mergeStateStatus: 'CLEAN',
    statusCheckRollup: [
      { name: 'Lint', conclusion: 'SUCCESS' },
      { name: 'Tests', conclusion: 'SUCCESS' },
      { name: 'Reply', conclusion: 'SKIPPED' },
    ],
    ...overrides,
  })
}

function engine(on: On, pr: string) {
  mock.clock(on, { now: 0 })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('process.run', (_, e) => {
    const stdout = e.argv[0] === 'gh' ? pr : 'feat/some-branch\n'
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
}

test('the band shows PR state, title and CI on one row, without the branch or URL', async ($, on) => {
  engine(on, prJson())
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect(await ui.find({ type: 'Text', text: / OPEN #223 / })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'feat(mods): add a pane' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /CI green/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: '✓2' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: '⤼1' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /feat\/some-branch/ })).toBeUndefined()
    expect(await ui.find({ type: 'Link' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /failed:/ })).toBeUndefined()
    await ui.unmount()
  }
})

test('a failing check and a conflict add a second row', async ($, on) => {
  engine(on, prJson({ mergeable: 'CONFLICTING', statusCheckRollup: [{ name: 'Tests', conclusion: 'FAILURE' }] }))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /failed:/ }))?.text).toBe('failed: Tests')
  expect(await ui.find({ type: 'Text', text: '⚑ merge conflict' })).toBeDefined()
  await ui.unmount()
})
