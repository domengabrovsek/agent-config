export type Focus =
  | { status: 'idle' }
  | { status: 'ok'; summary: string; updatedAt: number; error?: string }
  | { status: 'error'; message: string }

declare module 'claude-code' {
  interface PluginState {
    'session-focus': {
      prompts: Shaped<string[]>
      focus: Shaped<Focus>
    }
  }
}
