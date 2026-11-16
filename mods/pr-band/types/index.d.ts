export type Overall = 'pass' | 'fail' | 'waiting' | 'pending' | 'none'

export type CiSummary = {
  overall: Overall
  passed: number
  failed: string[]
  running: string[]
  waiting: string[]
  skipped: number
}

export type Pr = {
  number: number
  state: string
  isDraft: boolean
  title: string
  ci: CiSummary
  attention: string[]
}

export type PrInfo = {
  checkedAt: number
  pr: Pr | null
}

declare module 'claude-code' {
  interface PluginState {
    'pr-band': { info: PrInfo | null }
  }
}
