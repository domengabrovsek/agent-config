import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

const FLEET = {
  command: 'fleet',
  args: '',
  origin: { kind: 'composer' },
  presentation: { isFullscreen: true, columns: 160 },
} as const

const PANE = {
  plugin: 'pr-fleet',
  component: 'Pane',
  requestId: 'pr-fleet',
  props: {
    title: 'PR fleet',
    isFocused: false,
    bodyColumns: 80,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 30 },
    view: {},
  },
} as const

const SEARCH = JSON.stringify({
  data: {
    search: {
      issueCount: 2,
      nodes: [
        {
          number: 7,
          title: 'feat: second',
          url: 'https://github.com/acme/web/pull/7',
          isDraft: false,
          repository: { nameWithOwner: 'acme/web' },
          reviewDecision: 'CHANGES_REQUESTED',
          mergeStateStatus: 'DIRTY',
          commits: { nodes: [{ commit: { statusCheckRollup: { state: 'FAILURE' } } }] },
          reviewThreads: { nodes: [{ isResolved: false }, { isResolved: true }, { isResolved: false }] },
        },
        {
          number: 3,
          title: 'fix: first',
          url: 'https://github.com/acme/api/pull/3',
          isDraft: true,
          repository: { nameWithOwner: 'acme/api' },
          reviewDecision: null,
          mergeStateStatus: 'CLEAN',
          commits: { nodes: [{ commit: { statusCheckRollup: { state: 'SUCCESS' } } }] },
          reviewThreads: { nodes: [] },
        },
      ],
    },
  },
})

const ran = (exitCode: number, stdout: string, stderr = '') => ({
  value: { exitCode, stdout, stderr, isStdoutTruncated: false, isStderrTruncated: false },
})

function engine(on: On) {
  mock.clock(on)
  on('command.register', () => ({ value: { command: 'fleet' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
}

test('the pane lists each PR with CI, review, threads and merge state', async ($, on) => {
  engine(on)
  on('process.run', () => ran(0, SEARCH))

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.command.run(FLEET)

  for (const surface of ['terminal', 'desktop', 'vscode', 'mobile'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /open PRs/ }))?.text).toBe('2 open PRs')
    expect(await ui.find({ type: 'Text', text: 'changes requested' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: '2 unresolved' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'conflict' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'ready' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'draft' })).toBeDefined()
    await ui.unmount()
  }
})

test('a missing gh shows how to install it', async ($, on) => {
  engine(on)
  on('process.run', () => {
    throw new Error('spawn gh ENOENT')
  })

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.command.run(FLEET)

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /gh is not installed/ }))?.text).toBeDefined()
  await ui.unmount()
})

test('a signed-out gh asks for gh auth login', async ($, on) => {
  engine(on)
  on('process.run', () => ran(4, '', 'To get started with GitHub CLI, please run:  gh auth login'))

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.command.run(FLEET)

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /gh auth login/ }))?.text).toBe('gh is not signed in. Run gh auth login.')
  await ui.unmount()
})

test('a gh that times out is not reported as missing', async ($, on) => {
  engine(on)
  on('process.run', (_, e) => {
    if (e.argv.includes('--version')) return ran(0, 'gh version 2.0.0')
    throw new Error('timed out')
  })

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.command.run(FLEET)

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /timed out/ }))?.text).toBe('gh timed out searching your PRs. Refresh to try again.')
  await ui.unmount()
})
