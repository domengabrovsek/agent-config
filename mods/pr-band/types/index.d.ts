export type Overall = 'pass' | 'fail' | 'waiting' | 'pending' | 'none'

export type Ci = {
  overall: Overall
  passed: number
  failed: string[]
  running: string[]
  waiting: string[]
  skipped: number
}

export type Pr = {
  number: number
  url: string
  state: string
  isDraft: boolean
  title: string
  ci: Ci
  attention: string[]
}

export type Worktree = { name: string; isLinked: boolean }

export type PrInfo = {
  branch: string
  worktree: Worktree
  checkedAt: number
  pr: Pr | null
}

declare module 'claude-code' {
  interface PluginState {
    'pr-band': { info: PrInfo | null }
  }
}
