/**
 * Pure footer formatting for the statusline extension: token and countdown
 * text, usage-window parsing and colors, and segment layout. Text width comes
 * in through TextMeasure, so the module needs no pi-tui at runtime and
 * `node --test` loads it directly.
 */

import { basename } from 'node:path';

import type { UsageWindow } from './usage.ts';

export type ColorToken = 'success' | 'warning' | 'error' | 'dim' | 'accent';

/** The subset of Theme methods the footer needs (structural, theme-agnostic). */
export interface FooterStyle {
  fg(token: ColorToken, text: string): string;
  bold(text: string): string;
}

/** Same compaction as pi's own footer formatTokens. */
export function formatTokens(count: number): string {
  if (count < 1000) return count.toString();
  if (count < 10000) return `${(count / 1000).toFixed(1)}k`;
  if (count < 1000000) return `${Math.round(count / 1000)}k`;
  if (count < 10000000) return `${(count / 1000000).toFixed(1)}M`;
  return `${Math.round(count / 1000000)}M`;
}

/** Seconds into a compact countdown: 2d 3h, 1h 52m, 14m, <1m. */
export function humanizeReset(seconds: number): string {
  if (seconds <= 0) return '';
  if (seconds < 60) return '<1m';
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  if (hours < 48) return `${hours}h ${minutes % 60}m`;
  return `${Math.floor(hours / 24)}d ${hours % 24}h`;
}

const num = (v: string | undefined): number | null => {
  if (v === undefined) return null;
  const n = parseFloat(v);
  return Number.isFinite(n) ? n : null;
};

export interface UsageWindows {
  /** Provider id of the model that produced these headers. */
  provider: string;
  fiveHour: UsageWindow | null;
  sevenDay: UsageWindow | null;
  /** Capture time, ms epoch; the footer ages stale windows out. */
  capturedAt: number;
}

const REJECTED_STATUS = /rejected|rate_limited|exceeded|blocked/;

const windowFrom = (
  utilFrac: number | null,
  utilReset: number | null,
  rawStatus: string | undefined,
): UsageWindow | null => {
  if (utilFrac === null && utilReset === null && rawStatus === undefined) return null;
  return {
    pct: utilFrac === null ? null : Math.round(Math.min(Math.max(utilFrac, 0), 9.99) * 100),
    resetEpochSec: utilReset !== null && utilReset > 0 ? Math.round(utilReset) : null,
    rejected: REJECTED_STATUS.test(rawStatus ?? ''),
  };
};

/** Parse anthropic-ratelimit-unified-* headers (utilization is a 0..1 float). */
export function parseUnifiedHeaders(
  headers: Record<string, string>,
): Pick<UsageWindows, 'fiveHour' | 'sevenDay'> | undefined {
  const fiveHour = windowFrom(
    num(headers['anthropic-ratelimit-unified-5h-utilization']),
    num(headers['anthropic-ratelimit-unified-5h-reset']),
    headers['anthropic-ratelimit-unified-5h-status'],
  );
  const sevenDay = windowFrom(
    num(headers['anthropic-ratelimit-unified-7d-utilization']),
    num(headers['anthropic-ratelimit-unified-7d-reset']),
    headers['anthropic-ratelimit-unified-7d-status'],
  );
  return fiveHour || sevenDay ? { fiveHour, sevenDay } : undefined;
}

/** Green/yellow/red at the statusline's 50%/80% thresholds. */
export function usageColorName(pct: number, binding: boolean): ColorToken {
  if (binding || pct >= 80) return 'error';
  if (pct >= 50) return 'warning';
  return 'success';
}

/* ---------------------------------------------------------------------------
 * Line assembly
 * --------------------------------------------------------------------------- */

const SEP = ' │ ';

export interface Seg {
  text: string;
  /**
   * Drop priority: segments drop right-to-left (model=1, usage=2, spend=3)
   * under width pressure; segments without a priority are never dropped.
   */
  drop?: 1 | 2 | 3;
}

export interface LiveFooter {
  cwd: string;
  branch: string | null;
  dirty: boolean | undefined;
  spendParts: string[];
  context: { tokens: number; percent: number } | undefined;
  windows?: UsageWindows;
  nowSec: number;
  modelId: string | undefined;
  thinkingLevel?: string;
}

function usageSegment(
  theme: FooterStyle,
  windows: UsageWindows,
  nowSec: number,
): Seg | undefined {
  const ageSec = nowSec - Math.floor(windows.capturedAt / 1000);
  if (ageSec >= 3600) return undefined; // too stale to be honest
  const parts: string[] = [];
  for (const [win, fallbackLabel] of [
    [windows.fiveHour, '5h'],
    [windows.sevenDay, '7d'],
  ] as const) {
    if (!win) continue;
    const label = win.label ?? fallbackLabel;
    const color: ColorToken = ageSec >= 600 ? 'dim' : usageColorName(win.pct ?? 0, win.rejected);
    const resetSuffix =
      win.resetEpochSec !== null && win.resetEpochSec > nowSec
        ? ` ${theme.fg('dim', `(${humanizeReset(win.resetEpochSec - nowSec)})`)}`
        : '';
    parts.push(`${theme.fg(color, `${label} ${win.pct ?? 0}%`)}${resetSuffix}`);
  }
  return parts.length > 0 ? { text: parts.join(' '), drop: 2 } : undefined;
}

/**
 * Build the footer segments in display order. Context and branch stay until the
 * line runs out of width; model, usage windows, and spend drop in that order.
 */
export function buildSegs(theme: FooterStyle, live: Omit<LiveFooter, 'windows'> & { windows?: UsageWindows }): Seg[] {
  const segs: Seg[] = [];

  segs.push({ text: theme.bold(basename(live.cwd)) });

  if (live.branch) {
    const dirty = live.dirty === true;
    const color: ColorToken = live.branch === 'detached' ? 'dim' : dirty ? 'error' : 'success';
    segs.push({ text: `${theme.fg('dim', 'on')} ${theme.fg(color, `${live.branch}${dirty ? '*' : ''}`)}` });
  }

  if (live.spendParts.length > 0) segs.push({ text: theme.fg('dim', live.spendParts.join(' ')), drop: 3 });

  if (live.context) {
    const pct = Math.round(live.context.percent);
    segs.push({
      text: `${theme.fg('accent', 'context')} ${theme.fg(usageColorName(pct, false), `${formatTokens(live.context.tokens)} (${pct}%)`)}`,
    });
  } else {
    segs.push({ text: `${theme.fg('accent', 'context')} ${theme.fg('dim', '-')}` });
  }

  if (live.windows) {
    const usage = usageSegment(theme, live.windows, live.nowSec);
    if (usage) segs.push(usage);
  }

  if (live.modelId) {
    segs.push({
      text: theme.fg('dim', live.thinkingLevel ? `${live.modelId} · ${live.thinkingLevel}` : live.modelId),
      drop: 1,
    });
  }

  return segs;
}

/** Terminal text width, as pi-tui measures and truncates it. */
export interface TextMeasure {
  visibleWidth(text: string): number;
  truncateToWidth(text: string, width: number): string;
}

export interface AssembleOptions {
  theme: FooterStyle;
  width: number;
  measure: TextMeasure;
}

/** Drop by drop-priority (1=model, 2=usage, 3=spend) until the line fits, then hard-truncate. */
export function assembleLine(segs: Seg[], options: AssembleOptions): string {
  const { theme, width, measure } = options;
  const sep = theme.fg('dim', SEP);
  const join = (pool: Seg[]): string => pool.map((s) => s.text).join(sep);
  let pool = [...segs];
  let line = join(pool);
  while (measure.visibleWidth(line) > width && pool.length > 1) {
    let dropIdx = -1;
    let best = Number.POSITIVE_INFINITY;
    pool.forEach((seg, i) => {
      const prio = seg.drop ?? Number.POSITIVE_INFINITY;
      if (prio < best) {
        best = prio;
        dropIdx = i;
      }
    });
    if (!Number.isFinite(best)) break; // nothing droppable left
    pool = pool.filter((_, i) => i !== dropIdx);
    line = join(pool);
  }
  return measure.truncateToWidth(line, width);
}
