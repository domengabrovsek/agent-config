import { Buffer } from 'node:buffer';

export interface UsageWindow {
  pct: number | null;
  resetEpochSec: number | null;
  rejected: boolean;
  label?: string;
}

export interface ParsedUsageWindows {
  fiveHour: UsageWindow | null;
  sevenDay: UsageWindow | null;
}

export type JsonValue = null | boolean | number | string | JsonObject | JsonValue[];

interface JsonObject {
  [key: string]: JsonValue;
}

function asObject(value: JsonValue | undefined): JsonObject | undefined {
  return value !== null && typeof value === 'object' && !Array.isArray(value) ? value : undefined;
}

function finiteNumber(value: JsonValue | undefined): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

export function formatWindowLabel(seconds: number): string | undefined {
  if (!Number.isFinite(seconds) || seconds <= 0) return undefined;
  const rounded = Math.round(seconds);
  if (rounded % 86_400 === 0) return `${rounded / 86_400}d`;
  if (rounded % 3_600 === 0) return `${rounded / 3_600}h`;
  if (rounded % 60 === 0) return `${rounded / 60}m`;
  return `${rounded}s`;
}

function parseWindow(value: JsonValue | undefined, rejected: boolean): UsageWindow | null {
  const raw = asObject(value);
  if (!raw) return null;
  const pct = finiteNumber(raw.used_percent);
  let resetEpochSec = finiteNumber(raw.reset_at);
  if (resetEpochSec !== null && resetEpochSec > 1e12) resetEpochSec /= 1000;
  if (pct === null && resetEpochSec === null) return null;

  const windowSeconds = finiteNumber(raw.limit_window_seconds);
  return {
    pct: pct === null ? null : Math.round(Math.min(Math.max(pct, 0), 999)),
    resetEpochSec: resetEpochSec !== null && resetEpochSec > 0 ? Math.round(resetEpochSec) : null,
    rejected,
    label: windowSeconds === null ? undefined : formatWindowLabel(windowSeconds),
  };
}

export function parseCodexUsagePayload(payload: JsonValue): ParsedUsageWindows | undefined {
  const rateLimit = asObject(asObject(payload)?.rate_limit);
  if (!rateLimit) return undefined;
  const rejected = rateLimit.limit_reached === true || rateLimit.allowed === false;
  const fiveHour = parseWindow(rateLimit.primary_window, rejected);
  const sevenDay = parseWindow(rateLimit.secondary_window, rejected);
  return fiveHour || sevenDay ? { fiveHour, sevenDay } : undefined;
}

export function parseCodexHeaders(headers: Record<string, string>): ParsedUsageWindows | undefined {
  const num = (value: string | undefined): number | null => {
    if (value === undefined) return null;
    const parsed = parseFloat(value);
    return Number.isFinite(parsed) ? parsed : null;
  };
  const parse = (prefix: string): UsageWindow | null => {
    if (headers[`${prefix}-used-percent`] === undefined && headers[`${prefix}-reset-at`] === undefined) return null;
    const pct = num(headers[`${prefix}-used-percent`]);
    const windowMinutes = num(headers[`${prefix}-window-minutes`]);
    let resetEpoch = num(headers[`${prefix}-reset-at`]);
    if (resetEpoch !== null && resetEpoch > 1e12) resetEpoch /= 1000;
    return {
      pct: pct === null ? null : Math.round(Math.min(Math.max(pct, 0), 999)),
      resetEpochSec: resetEpoch !== null && resetEpoch > 0 ? Math.round(resetEpoch) : null,
      rejected: false,
      label: windowMinutes === null ? undefined : formatWindowLabel(windowMinutes * 60),
    };
  };
  const fiveHour = parse('x-codex-primary');
  const sevenDay = parse('x-codex-secondary');
  return fiveHour || sevenDay ? { fiveHour, sevenDay } : undefined;
}

export function extractOpenAIAccountId(token: string): string | undefined {
  const encodedPayload = token.split('.')[1];
  if (!encodedPayload) return undefined;

  try {
    const payload = asObject(JSON.parse(Buffer.from(encodedPayload, 'base64url').toString('utf8')) as JsonValue);
    const auth = asObject(payload?.['https://api.openai.com/auth']);
    const accountId = auth?.chatgpt_account_id;
    return typeof accountId === 'string' && accountId.length > 0 ? accountId : undefined;
  } catch {
    return undefined;
  }
}
