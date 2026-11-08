import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Focus } from '../types'

const KEEP = 6
const PROMPT_CHARS = 400

/* $.state lives as long as the process, and /clear keeps the process,
   so the prompts and summary carry over into the cleared conversation. */
const prompts = atom({ plugin: 'session-focus', key: 'prompts' } as const, [] as string[], { shape: 'prompts-1' })
const focus = atom({ plugin: 'session-focus', key: 'focus' } as const, { status: 'idle' } as Focus, { shape: 'focus-1' })

const SYSTEM =
  'You label what a developer is working on. Reply with 3 to 5 words in title case, naming the task. ' +
  'No punctuation, no quotes, no preamble. Weight the latest requests most.'

let latest = 0

/* herdr shows the label as the $focus token in its agent sidebar. herdr keeps
   the token per pane, past this process and until a herdr restart, so each sync
   sends the current label, or clears a token another session left in the pane. */
let syncing: Promise<void> = Promise.resolve()

/* Syncs run one at a time, each reading the label when it starts, so an older
   label never lands after a newer one. */
function syncHerdr($: EngineInterface): Promise<void> {
  syncing = syncing.then(() => sendToHerdr($)).catch(() => undefined)
  return syncing
}

async function sendToHerdr($: EngineInterface): Promise<void> {
  const pane = await $.env.get('HERDR_PANE_ID')
  if (!pane) return
  const current = await read($, focus)
  const token = current.status === 'ok' ? ['--token', `focus=${current.summary}`] : ['--clear-token', 'focus']
  await $.process.run(['herdr', 'pane', 'report-metadata', pane, '--source', 'agent-config:session-focus', ...token], {
    timeoutMs: 5000,
  })
}

async function summarize($: EngineInterface, recent: string[]): Promise<void> {
  const seq = ++latest
  const prompt = recent.map((text, i) => `Request ${i + 1}:\n${text}`).join('\n\n')
  const reply = await $.model.complete({ model: 'haiku', system: SYSTEM, prompt, maxTokens: 30, effort: 'low', timeoutMs: 15000 })
  /* A newer prompt started its own call, so this reply is stale. */
  if (seq !== latest) return
  const updatedAt = await $.clock.now()
  if (reply.isAnswered) {
    const summary = (reply.text.trim().split('\n')[0] ?? '').replace(/[."']/g, '').slice(0, 60)
    if (summary) {
      await update($, focus, (): Focus => ({ status: 'ok', summary, updatedAt }))
      await syncHerdr($)
      return
    }
  }
  const error = reply.isAnswered ? 'empty reply' : reply.reason
  await update($, focus, (current): Focus =>
    current.status === 'ok' ? { ...current, error } : { status: 'error', message: `Summary failed: ${error}` },
  )
}

function clockTime(ms: number): string {
  const d = new Date(ms)
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    void syncHerdr($)
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    /* Resends the label a herdr restart or a hot reload may have dropped. */
    void syncHerdr($)
    const text = e.text.trim()
    const typed = e.origin.kind === 'composer' || e.origin.kind === 'bridge'
    if (typed && !e.command && !e.isMeta && text) {
      const recent = [...(await read($, prompts)), text.slice(0, PROMPT_CHARS)].slice(-KEEP)
      await update($, prompts, () => recent)
      summarize($, recent).catch(() => undefined)
    }
    return next(e)
  })

  /* Plugins listed earlier in CLAUDE_CODE_PLUGIN_DIRS run outermost, and pr-band
     answers without calling next, so this mod is listed first and draws its row
     above whatever the plugins beneath draw. */
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const current = await read($, focus)
    if (e.props.hasSurvey || current.status === 'idle') {
      return next(e)
    }

    const { Box, Text } = $.ui.resolve(e)
    const beneath = await next(e)
    const row =
      current.status === 'error' ? (
        <Box paddingX={1}>
          <Text color="error" wrap="truncate-end">{current.message}</Text>
        </Box>
      ) : (
        <Box paddingX={1} gap={2}>
          <Box flexGrow={1} flexShrink={1}>
            <Text wrap="truncate-end">
              <Text color="suggestion">▸ </Text>
              <Text bold>{current.summary}</Text>
            </Text>
          </Box>
          <Box flexShrink={0}>
            <Text dimColor>
              {current.error ? `update failed: ${current.error} · ` : ''}↻ {clockTime(current.updatedAt)}
            </Text>
          </Box>
        </Box>
      )

    return (
      <Box flexDirection="column">
        {row}
        {beneath}
      </Box>
    )
  })
}
