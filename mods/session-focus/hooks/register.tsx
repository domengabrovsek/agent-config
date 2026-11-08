import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Focus } from '../types'

const PANE = 'session-focus'
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
    await $.command.register({ name: 'session-focus', description: 'Show what this terminal session is working on' })
    await $.ui.open({ id: PANE, title: 'Focus' })
    return next(e)
  })

  on('command.run', { command: 'session-focus' }, async $ => {
    await $.ui.open({ id: PANE, title: 'Focus' })
    return { text: 'Focus pane opened.' }
  })

  on('prompt.submit', async ($, e, next) => {
    const text = e.text.trim()
    const typed = e.origin.kind === 'composer' || e.origin.kind === 'bridge'
    if (typed && !e.command && !e.isMeta && text) {
      const recent = [...(await read($, prompts)), text.slice(0, PROMPT_CHARS)].slice(-KEEP)
      await update($, prompts, () => recent)
      summarize($, recent).catch(() => undefined)
    }
    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const current = await read($, focus)

    if (current.status === 'idle') {
      return <Text dimColor>No prompts yet.</Text>
    }
    if (current.status === 'error') {
      return <Text color="error">{current.message}</Text>
    }
    return (
      <Box flexDirection="column">
        <Text bold>{current.summary}</Text>
        <Text dimColor>
          updated {clockTime(current.updatedAt)}
          {current.error ? ` · last update failed: ${current.error}` : ''}
        </Text>
      </Box>
    )
  })
}
