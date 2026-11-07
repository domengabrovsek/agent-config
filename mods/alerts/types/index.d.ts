export type Alert = {
  shortId: string
  title: string
  url: string
  project: string
  occurrences: number
  users: number
  lastSeen: string
}

export type Alerts =
  | { status: 'ok'; checkedAt: number; searchUrl: string; issues: Alert[] }
  | { status: 'error'; checkedAt: number; message: string }

declare module 'claude-code' {
  interface PluginState {
    alerts: { alerts: Shaped<Alerts | null> }
  }
}
