export type Ci = 'pass' | 'fail' | 'pending' | 'none'

export type FleetPr = {
  repo: string
  number: number
  title: string
  url: string
  isDraft: boolean
  ci: Ci
  review: string
  unresolved: number
  mergeState: string
}

export type Fleet =
  | { status: 'ok'; checkedAt: number; total: number; prs: FleetPr[] }
  | { status: 'error'; checkedAt: number; message: string }

declare module 'claude-code' {
  interface PluginState {
    'pr-fleet': { fleet: Shaped<Fleet | null> }
  }
}
