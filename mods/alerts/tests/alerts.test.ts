import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

const ALERTS = {
  command: 'alerts',
  args: '',
  origin: { kind: 'composer' },
  presentation: { isFullscreen: true, columns: 160 },
} as const

const PANE = {
  plugin: 'alerts',
  component: 'Pane',
  requestId: 'alerts',
  props: {
    title: 'Sentry alerts',
    isFocused: false,
    bodyColumns: 80,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 30 },
    view: {},
  },
} as const

const SEARCH = JSON.stringify({
  url: 'https://example.sentry.io/issues/?query=is%3Aunresolved',
  issues: [
    {
      shortId: 'WEB-1A',
      title: 'TypeError: cannot read properties of undefined',
      url: 'https://example.sentry.io/issues/WEB-1A',
      projectSlug: 'web',
      occurrences: 12,
      usersImpacted: 3,
      lastSeen: '1970-01-01T00:00:00Z',
    },
  ],
})

function engine(on: On) {
  mock.clock(on, { now: 2 * 3600000 })
  on('command.register', () => ({ value: { command: 'alerts' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
}

test('the pane lists each unresolved issue with its counts and link', async ($, on) => {
  engine(on)
  on('mcp.call', () => ({ value: { content: [{ type: 'text', text: SEARCH }], isError: false } }))

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.command.run(ALERTS)

  for (const surface of ['terminal', 'desktop', 'vscode', 'mobile'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /unresolved in 24h/ }))?.text).toBe('1 unresolved in 24h')
    expect(await ui.find({ type: 'Text', text: '12x' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: '3 users' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: '2h ago' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /cannot read properties/ })).toBeDefined()
    await ui.unmount()
  }
})

function searchOf(count: number): string {
  const issue = JSON.parse(SEARCH).issues[0]
  return JSON.stringify({
    url: JSON.parse(SEARCH).url,
    issues: Array.from({ length: count }, (_, i) => ({ ...issue, shortId: `WEB-${i}`, url: `${issue.url}-${i}`, usersImpacted: 1 })),
  })
}

test('a list at the search cap reads as capped, with singular user counts', async ($, on) => {
  engine(on)
  on('mcp.call', () => ({ value: { content: [{ type: 'text', text: searchOf(25) }], isError: false } }))

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.command.run(ALERTS)

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /unresolved in 24h/ }))?.text).toBe('25+ unresolved in 24h')
  expect(await ui.find({ type: 'Text', text: '1 user' })).toBeDefined()
  await ui.unmount()
})

test('an empty search says there are no unresolved issues', async ($, on) => {
  engine(on)
  on('mcp.call', () => ({ value: { content: [{ type: 'text', text: searchOf(0) }], isError: false } }))

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.command.run(ALERTS)

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /unresolved in 24h/ }))?.text).toBe('0 unresolved in 24h')
  expect(await ui.find({ type: 'Text', text: 'No unresolved issues in the last 24 hours.' })).toBeDefined()
  await ui.unmount()
})

test('a call that rejects shows its error and how to connect the server', async ($, on) => {
  engine(on)

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.command.run(ALERTS)

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /call failed/ }))?.text).toBe(
    'Sentry call failed: no implementation for mcp.call. If the server is not connected, connect it with /mcp.',
  )
  await ui.unmount()
})

test('a failed search shows the server error', async ($, on) => {
  engine(on)
  on('mcp.call', () => ({ value: { content: [{ type: 'text', text: 'Authentication required' }], isError: true } }))

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.command.run(ALERTS)

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /search failed/ }))?.text).toBe('Sentry search failed: Authentication required')
  await ui.unmount()
})
