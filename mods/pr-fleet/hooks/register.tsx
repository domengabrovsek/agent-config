import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, ThemeKey } from 'claude-code'

import type { Ci, Fleet, FleetPr } from '../types'

type RawPr = {
  number: number
  title: string
  url: string
  isDraft: boolean
  repository: { nameWithOwner: string }
  reviewDecision: string | null
  mergeStateStatus: string
  commits: { nodes: { commit: { statusCheckRollup: { state: string } | null } }[] }
  reviewThreads: { nodes: { isResolved: boolean }[] }
}

type RawSearch = { data?: { search: { issueCount: number; nodes: (RawPr | Record<string, never>)[] } } }

const PANE = 'pr-fleet'
const LIMIT = 50

/* One GraphQL search costs a single rate-limit point and returns CI, review,
   thread and merge state together, where `gh search prs` has none of them
   and a `gh pr view` per PR would cost one call each. */
const QUERY = `query {
  search(query: "is:pr is:open author:@me archived:false", type: ISSUE, first: ${LIMIT}) {
    issueCount
    nodes { ... on PullRequest {
      number title url isDraft
      repository { nameWithOwner }
      reviewDecision mergeStateStatus
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      reviewThreads(first: 100) { nodes { isResolved } }
    } }
  }
}`

const fleet = atom({ plugin: 'pr-fleet', key: 'fleet' } as const, null, { shape: 'fleet-1' })

function ciOf(state: string | undefined): Ci {
  if (state === 'SUCCESS') return 'pass'
  if (state === 'FAILURE' || state === 'ERROR') return 'fail'
  if (state === 'PENDING' || state === 'EXPECTED') return 'pending'
  return 'none'
}

function parse(stdout: string): { total: number; prs: FleetPr[] } {
  const search = (JSON.parse(stdout) as RawSearch).data?.search
  const prs = (search?.nodes ?? [])
    .filter((node): node is RawPr => 'number' in node)
    .map(raw => ({
      repo: raw.repository.nameWithOwner,
      number: raw.number,
      title: raw.title,
      url: raw.url,
      isDraft: raw.isDraft,
      ci: ciOf(raw.commits.nodes[0]?.commit.statusCheckRollup?.state),
      review: raw.reviewDecision ?? '',
      unresolved: raw.reviewThreads.nodes.filter(thread => !thread.isResolved).length,
      mergeState: raw.mergeStateStatus,
    }))
    .sort((a, b) => a.repo.localeCompare(b.repo) || a.number - b.number)
  return { total: search?.issueCount ?? prs.length, prs }
}

async function load($: EngineInterface): Promise<Fleet> {
  const checkedAt = await $.clock.now()
  let ran
  try {
    ran = await $.process.run(['gh', 'api', 'graphql', '-f', `query=${QUERY}`], { timeoutMs: 20000 })
  } catch {
    return { status: 'error', checkedAt, message: 'gh is not installed or not on PATH. Install the GitHub CLI.' }
  }
  if (ran.exitCode !== 0) {
    const signedOut = /auth login|not logged in|authenticat/i.test(ran.stderr)
    const message = signedOut ? 'gh is not signed in. Run gh auth login.' : `gh failed: ${ran.stderr.trim().split('\n')[0] ?? 'no output'}`
    return { status: 'error', checkedAt, message }
  }
  try {
    return { status: 'ok', checkedAt, ...parse(ran.stdout) }
  } catch {
    return { status: 'error', checkedAt, message: 'gh returned output the pane cannot read.' }
  }
}

async function refresh($: EngineInterface): Promise<void> {
  const next = await load($)
  await update($, fleet, () => next)
}

const CI: Record<Ci, { icon: string; color: ThemeKey }> = {
  pass: { icon: '✓', color: 'success' },
  fail: { icon: '✗', color: 'error' },
  pending: { icon: '◌', color: 'warning' },
  none: { icon: '·', color: 'subtle' },
}

function reviewFlag(review: string): { text: string; color: ThemeKey } | null {
  if (review === 'APPROVED') return { text: 'approved', color: 'success' }
  if (review === 'CHANGES_REQUESTED') return { text: 'changes requested', color: 'error' }
  if (review === 'REVIEW_REQUIRED') return { text: 'review needed', color: 'warning' }
  return null
}

function mergeFlag(state: string): { text: string; color: ThemeKey } | null {
  if (state === 'CLEAN') return { text: 'ready', color: 'success' }
  if (state === 'DIRTY') return { text: 'conflict', color: 'error' }
  if (state === 'BEHIND') return { text: 'behind', color: 'warning' }
  if (state === 'BLOCKED') return { text: 'blocked', color: 'permission' }
  if (state === 'UNSTABLE') return { text: 'unstable', color: 'warning' }
  return null
}

function clockTime(ms: number): string {
  const d = new Date(ms)
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'fleet', description: 'Show your open PRs across all repos in a pane' })
    /* The timer polls only once /fleet has filled the state, so sessions that
       never open the pane spend no GitHub rate limit. */
    $.clock.every(60000, () => {
      read($, fleet)
        .then(current => (current === null ? undefined : refresh($)))
        .catch(() => undefined)
    })
    return next(e)
  })

  on('command.run', { command: 'fleet' }, async $ => {
    await $.ui.open({ id: PANE, title: 'PR fleet' })
    await refresh($)
    return { text: 'PR fleet pane opened.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Link, Button } = $.ui.resolve(e)
    const current = await read($, fleet)

    const header = (
      <Box gap={2} justifyContent="space-between">
        <Text bold>
          {current?.status === 'ok' ? `${current.total} open PRs` : 'Open PRs'}
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
        {current.prs.length === 0 ? <Text dimColor>No open PRs.</Text> : null}
        {current.prs.map(pr => {
          const ci = CI[pr.ci]
          const review = reviewFlag(pr.review)
          const merge = mergeFlag(pr.mergeState)
          return (
            <Box flexDirection="column">
              <Box gap={1}>
                <Text color={ci.color} bold>{ci.icon}</Text>
                <Text bold><Link href={pr.url} label={`${pr.repo}#${pr.number}`} /></Text>
                {pr.isDraft ? <Text dimColor>draft</Text> : null}
                {review ? <Text color={review.color}>{review.text}</Text> : null}
                {pr.unresolved > 0 ? <Text color="permission">{pr.unresolved} unresolved</Text> : null}
                {merge ? <Text color={merge.color}>{merge.text}</Text> : null}
              </Box>
              <Text dimColor wrap="truncate-end">  {pr.title}</Text>
            </Box>
          )
        })}
        {current.total > current.prs.length ? <Text dimColor>+{current.total - current.prs.length} more on GitHub</Text> : null}
      </Box>
    )
  })
}
