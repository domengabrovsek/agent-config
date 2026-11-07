import { atom, read, update } from 'claude-code'
import type { EngineInterface, McpToolResult, Register } from 'claude-code'

import type { Alert, Alerts } from '../types'

type RawIssue = {
  shortId: string
  title: string
  url: string
  projectSlug?: string
  occurrences?: number
  usersImpacted?: number
  lastSeen?: string
}

type RawSearch = { url?: string; issues?: RawIssue[] }

const PANE = 'alerts'
const SERVER = 'sentry'
/* Each search runs on Sentry's side and may pass through its query agent,
   so the pane polls every five minutes rather than every minute. */
const EVERY_MS = 5 * 60000

const alerts = atom({ plugin: 'alerts', key: 'alerts' } as const, null, { shape: 'alerts-1' })

function textOf(result: McpToolResult): string {
  return result.content.map(block => (typeof block.text === 'string' ? block.text : '')).join('')
}

function parse(text: string): { searchUrl: string; issues: Alert[] } {
  const raw = JSON.parse(text) as RawSearch
  const issues = (raw.issues ?? []).map(issue => ({
    shortId: issue.shortId,
    title: issue.title,
    url: issue.url,
    project: issue.projectSlug ?? '',
    occurrences: issue.occurrences ?? 0,
    users: issue.usersImpacted ?? 0,
    lastSeen: issue.lastSeen ?? '',
  }))
  return { searchUrl: raw.url ?? '', issues }
}

const LIMIT = 25

async function load($: EngineInterface): Promise<Alerts> {
  const checkedAt = await $.clock.now()
  let result: McpToolResult
  try {
    result = await $.mcp.call(SERVER, 'search_issues', {
      query: 'is:unresolved',
      period: '24h',
      sort: 'date',
      limit: LIMIT,
    })
  } catch (err) {
    const detail = (err instanceof Error ? err.message : String(err)).trim().split('\n')[0] || 'no detail'
    /* The engine reports no connection status, so the real error leads and the /mcp hint follows. */
    return { status: 'error', checkedAt, message: `Sentry call failed: ${detail}. If the server is not connected, connect it with /mcp.` }
  }
  const text = textOf(result)
  if (result.isError) {
    return { status: 'error', checkedAt, message: `Sentry search failed: ${text.trim().split('\n')[0] || 'no detail'}` }
  }
  try {
    return { status: 'ok', checkedAt, ...parse(text) }
  } catch {
    return { status: 'error', checkedAt, message: 'Sentry returned output the pane cannot read.' }
  }
}

async function refresh($: EngineInterface): Promise<void> {
  const next = await load($)
  await update($, alerts, () => next)
}

function ago(iso: string, now: number): string {
  const then = Date.parse(iso)
  if (Number.isNaN(then)) return ''
  const minutes = Math.max(0, Math.round((now - then) / 60000))
  if (minutes < 60) return `${minutes}m ago`
  return `${Math.round(minutes / 60)}h ago`
}

function clockTime(ms: number): string {
  const d = new Date(ms)
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'alerts', description: 'Show unresolved Sentry issues from the last 24 hours in a pane' })
    /* The timer polls only once /alerts has filled the state, so sessions
       that never open the pane make no Sentry calls. */
    $.clock.every(EVERY_MS, () => {
      read($, alerts)
        .then(current => (current === null ? undefined : refresh($)))
        .catch(() => undefined)
    })
    return next(e)
  })

  on('command.run', { command: 'alerts' }, async $ => {
    await $.ui.open({ id: PANE, title: 'Sentry alerts' })
    await refresh($)
    return { text: 'Sentry alerts pane opened.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Link, Button } = $.ui.resolve(e)
    const current = await read($, alerts)

    const header = (
      <Box gap={2} justifyContent="space-between">
        <Text bold>
          {current?.status === 'ok' ? `${current.issues.length}${current.issues.length === LIMIT ? '+' : ''} unresolved in 24h` : 'Sentry alerts'}
        </Text>
        <Box gap={1}>
          {current ? <Text dimColor>↻ {clockTime(current.checkedAt)}</Text> : null}
          <Button key="refresh" hotkey="r" label="refresh" onPress={() => refresh($)} />
        </Box>
      </Box>
    )

    if (current === null) {
      return <Box flexDirection="column">{header}<Text dimColor>Loading...</Text></Box>
    }
    if (current.status === 'error') {
      return <Box flexDirection="column">{header}<Text color="error">{current.message}</Text></Box>
    }

    return (
      <Box flexDirection="column">
        {header}
        {current.issues.length === 0 ? <Text color="success">No unresolved issues in the last 24 hours.</Text> : null}
        {current.issues.map(issue => (
          <Box key={issue.url} flexDirection="column">
            <Box gap={1}>
              <Text color="error" bold>✗</Text>
              <Text bold><Link href={issue.url} label={issue.shortId} /></Text>
              <Text dimColor>{issue.project}</Text>
              <Text color="warning">{issue.occurrences}x</Text>
              {issue.users > 0 ? <Text>{issue.users} user{issue.users === 1 ? '' : 's'}</Text> : null}
              <Text dimColor>{ago(issue.lastSeen, current.checkedAt)}</Text>
            </Box>
            <Text dimColor wrap="truncate-end">  {issue.title}</Text>
          </Box>
        ))}
        {current.searchUrl ? <Text dimColor><Link href={current.searchUrl} label="open in Sentry" /></Text> : null}
      </Box>
    )
  })
}
