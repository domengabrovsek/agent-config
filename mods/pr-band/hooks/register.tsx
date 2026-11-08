import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, ThemeKey } from 'claude-code'

import type { Ci, Overall, Pr } from '../types'

type Rollup = {
  name?: string | null
  context?: string | null
  status?: string | null
  conclusion?: string | null
  state?: string | null
}

type RawPr = {
  number: number
  url: string
  state: string
  isDraft: boolean
  title: string
  reviewDecision: string
  mergeable: string
  mergeStateStatus: string
  statusCheckRollup: Rollup[] | null
}

const info = atom({ plugin: 'pr-band', key: 'info' } as const, null)

const FAILED = new Set(['FAILURE', 'TIMED_OUT', 'CANCELLED', 'ACTION_REQUIRED', 'STARTUP_FAILURE', 'ERROR'])
const SKIPPED = new Set(['SKIPPED', 'NEUTRAL', 'STALE'])
const WAITING = new Set(['WAITING', 'ACTION_REQUIRED'])

function summarise(rollup: Rollup[]): Ci {
  const latest = new Map<string, Rollup>()
  for (const check of rollup) {
    latest.set(check.name ?? check.context ?? '?', check)
  }

  const ci: Ci = { overall: 'none', passed: 0, failed: [], running: [], waiting: [], skipped: 0 }
  for (const [name, check] of latest) {
    const result = check.conclusion ?? check.state ?? ''
    if (WAITING.has(check.status ?? '')) ci.waiting.push(name)
    else if (FAILED.has(result)) ci.failed.push(name)
    else if (SKIPPED.has(result)) ci.skipped += 1
    else if (result === 'SUCCESS') ci.passed += 1
    else ci.running.push(name)
  }

  if (ci.failed.length > 0) ci.overall = 'fail'
  else if (ci.waiting.length > 0) ci.overall = 'waiting'
  else if (ci.running.length > 0) ci.overall = 'pending'
  else if (ci.passed > 0) ci.overall = 'pass'
  return ci
}

function attentionFor(raw: RawPr): string[] {
  const items: string[] = []
  if (raw.reviewDecision === 'CHANGES_REQUESTED') items.push('changes requested')
  if (raw.mergeable === 'CONFLICTING') items.push('merge conflict')
  if (raw.mergeStateStatus === 'BEHIND') items.push('behind main')
  return items
}

const OVERALL: Record<Overall, { icon: string; text: string; color: ThemeKey }> = {
  pass: { icon: '✓', text: 'CI green', color: 'success' },
  fail: { icon: '✗', text: 'CI failed', color: 'error' },
  waiting: { icon: '⏸', text: 'CI waiting on you', color: 'permission' },
  pending: { icon: '◌', text: 'CI running', color: 'warning' },
  none: { icon: '·', text: 'no CI', color: 'subtle' },
}

function stateBadge(pr: Pr): { text: string; color: ThemeKey } {
  if (pr.state === 'MERGED') return { text: 'MERGED', color: 'merged' }
  if (pr.state === 'CLOSED') return { text: 'CLOSED', color: 'error' }
  if (pr.isDraft) return { text: 'DRAFT', color: 'subtle' }
  return { text: 'OPEN', color: 'success' }
}

function clockTime(ms: number): string {
  const d = new Date(ms)
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

function names(list: string[]): string {
  return list.length > 3 ? `${list.slice(0, 3).join(', ')} +${list.length - 3}` : list.join(', ')
}

async function refresh($: EngineInterface): Promise<void> {
  const head = await $.process.run(['git', 'branch', '--show-current'])
  const branch = head.stdout.trim()
  if (head.exitCode !== 0 || branch === '') {
    await update($, info, () => null)
    return
  }

  const view = await $.process.run(
    ['gh', 'pr', 'view', '--json', 'number,url,state,isDraft,title,reviewDecision,mergeable,mergeStateStatus,statusCheckRollup'],
    { timeoutMs: 15000 },
  )
  let pr: Pr | null = null
  if (view.exitCode === 0) {
    const raw = JSON.parse(view.stdout) as RawPr
    pr = {
      number: raw.number,
      url: raw.url,
      state: raw.state,
      isDraft: raw.isDraft,
      title: raw.title,
      ci: summarise(raw.statusCheckRollup ?? []),
      attention: attentionFor(raw),
    }
  }

  const previous = (await read($, info))?.pr
  if (previous?.ci && pr && previous.number === pr.number && previous.ci.overall !== pr.ci.overall && pr.ci.overall !== 'pending') {
    $.ui.toast(`PR #${pr.number}: ${OVERALL[pr.ci.overall].text}`)
  }
  const checkedAt = await $.clock.now()
  await update($, info, () => ({ branch, checkedAt, pr }))
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await refresh($).catch(() => undefined)
    $.clock.every(60000, () => {
      refresh($).catch(() => undefined)
    })
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    await refresh($).catch(() => undefined)
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const current = await read($, info)
    const pr = current?.pr ?? null
    if (e.props.hasSurvey || current === null || (pr !== null && pr.ci === undefined)) {
      return next(e)
    }

    /* The status line already shows the repo and branch, so the band leaves them
       out. A Link with no label draws the URL itself, which some terminals would
       otherwise print after the label. Only the title box may shrink, so nothing
       else wraps on a narrow terminal. */
    const { Box, Text, Link } = $.ui.resolve(e)
    const ci = pr?.ci ?? null
    const overall = ci ? OVERALL[ci.overall] : null
    const badge = pr ? stateBadge(pr) : null
    const borderColor: ThemeKey = pr && pr.attention.length > 0 && ci?.overall !== 'fail' ? 'permission' : (overall?.color ?? 'subtle')
    const details =
      pr !== null && ci !== null && (ci.failed.length > 0 || ci.waiting.length > 0 || pr.attention.length > 0)

    return (
      <Box borderStyle="round" borderColor={borderColor} paddingX={1} flexDirection="column">
        <Box gap={2}>
          {pr === null || badge === null ? (
            <Text dimColor italic>no PR yet</Text>
          ) : (
            <>
              <Box flexShrink={0}>
                <Text color="inverseText" backgroundColor={badge.color} bold> {badge.text} </Text>
              </Box>
              <Box flexShrink={0}>
                <Text bold><Link href={pr.url} /></Text>
              </Box>
              <Box flexGrow={1} flexShrink={1}>
                <Text wrap="truncate-end">{pr.title}</Text>
              </Box>
            </>
          )}
          {ci !== null && overall !== null ? (
            <Box gap={1} flexShrink={0}>
              <Text color={overall.color} bold>{overall.icon} {overall.text}</Text>
              {ci.passed > 0 ? <Text color="success">✓{ci.passed}</Text> : null}
              {ci.failed.length > 0 ? <Text color="error">✗{ci.failed.length}</Text> : null}
              {ci.running.length > 0 ? <Text color="warning">◌{ci.running.length}</Text> : null}
              {ci.skipped > 0 ? <Text dimColor>⤼{ci.skipped}</Text> : null}
            </Box>
          ) : null}
          {typeof current.checkedAt === 'number' ? (
            <Box flexShrink={0}>
              <Text dimColor>↻ {clockTime(current.checkedAt)}</Text>
            </Box>
          ) : null}
        </Box>
        {details && pr !== null && ci !== null ? (
          <Box gap={2} flexWrap="wrap">
            {ci.failed.length > 0 ? <Text color="error" wrap="truncate-end">failed: {names(ci.failed)}</Text> : null}
            {ci.waiting.length > 0 ? <Text color="permission" bold>⏸ approve: {names(ci.waiting)}</Text> : null}
            {pr.attention.map(item => <Text key={item} color="permission" bold>⚑ {item}</Text>)}
          </Box>
        ) : null}
      </Box>
    )
  })
}
