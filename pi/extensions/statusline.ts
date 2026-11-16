/**
 * statusline - pi footer styled after the Claude Code statusline
 * (~/.claude/statusline.sh, from the domengabrovsek/agent-config config repo).
 *
 * Replaces the built-in footer with one priority-ordered line:
 *
 *   folder │ on <branch>* │ ↑in ↓out Rcache Wcache $cost │ context 145k (34%) │ 5h 23% (1h52m) 7d 71% │ model · thinking
 *
 * Only context % and the usage-window percentages carry color (green/yellow/red
 * at 50%/80%); everything else is dim, so a red window reads at a glance.
 * Sections render only when their data exists - no fake zeros.
 *
 * Usage windows come from provider response headers. OpenAI Codex usage also
 * refreshes from the account usage endpoint because WebSocket responses do not
 * expose headers to extensions. The extension resolves runtime auth through pi
 * and never reads auth.json. Undocumented sources:
 *   - anthropic-ratelimit-unified-{5h,7d}-utilization / -reset / -status (OAuth)
 *   - x-codex-primary/secondary-used-percent response headers
 *   - OpenAI Codex /backend-api/wham/usage
 *
 * Window data is strictly per active provider: switching models to a different
 * provider clears the block until that provider's own first response. Fresh
 * windows are alert-colored, dim after 10 min, gone after 1 h.
 *
 * Portability: imports only the adjacent statusline/ modules, pi packages, and
 * node builtins.
 */

import { execFile } from 'node:child_process';

import { truncateToWidth, visibleWidth } from '@earendil-works/pi-tui';
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';
import {
  assembleLine,
  buildSegs,
  formatTokens,
  type LiveFooter,
  parseUnifiedHeaders,
  type UsageWindows,
} from './statusline/format.ts';
import {
  extractOpenAIAccountId,
  parseCodexHeaders,
  parseCodexUsagePayload,
  type JsonValue,
} from './statusline/usage.ts';

/* ---------------------------------------------------------------------------
 * Live state
 * --------------------------------------------------------------------------- */

let requestRenderFn: (() => void) | undefined;
let currentWindows: UsageWindows | undefined;
let unsubscribeBranch: (() => void) | undefined;
let usageRefreshAbort: AbortController | undefined;
let usageRefreshInFlight = false;
let usageLastAttemptAt = 0;

const DIRTY_TTL_MS = 60_000;
const USAGE_REFRESH_TTL_MS = 60_000;
const USAGE_REFRESH_TIMEOUT_MS = 5_000;
const CODEX_USAGE_URL = 'https://chatgpt.com/backend-api/wham/usage';
const gitState = {
  dirty: undefined as boolean | undefined,
  checkedAt: 0,
  inFlight: false,
  cwd: '',
};

function refreshGitDirty(ctx: { cwd: string }): void {
  if (gitState.inFlight) return;
  const now = Date.now();
  if (gitState.cwd === ctx.cwd && now - gitState.checkedAt < DIRTY_TTL_MS) return;
  gitState.inFlight = true;
  gitState.cwd = ctx.cwd;
  execFile(
    'git',
    ['-C', ctx.cwd, '-c', 'core.hooksPath=/dev/null', 'status', '--porcelain'],
    { cwd: ctx.cwd, timeout: 4000 },
    (err, stdout) => {
      gitState.inFlight = false;
      gitState.checkedAt = now;
      // No repo / empty repo / git broken: never show a dirty marker.
      gitState.dirty = err ? false : stdout.split('\n').some((line) => line.trim().length > 0);
      requestRenderFn?.();
    },
  );
}

function captureProviderHeaders(headers: Record<string, string>, provider: string): void {
  const normalized: Record<string, string> = {};
  for (const [k, v] of Object.entries(headers)) normalized[k.toLowerCase()] = v;
  const parsed = parseUnifiedHeaders(normalized) ?? parseCodexHeaders(normalized);
  if (parsed) currentWindows = { provider, ...parsed, capturedAt: Date.now() };
}

interface UsageRefreshContext {
  model?: { provider: string };
  modelRegistry: {
    getProviderAuth(provider: string): Promise<{ auth: { apiKey?: string } } | undefined>;
  };
}

async function refreshCodexUsage(ctx: UsageRefreshContext): Promise<void> {
  if (ctx.model?.provider !== 'openai-codex' || usageRefreshInFlight) return;
  const now = Date.now();
  if (now - usageLastAttemptAt < USAGE_REFRESH_TTL_MS) return;
  usageLastAttemptAt = now;
  usageRefreshInFlight = true;

  try {
    const resolved = await ctx.modelRegistry.getProviderAuth('openai-codex');
    const token = resolved?.auth.apiKey;
    const accountId = token ? extractOpenAIAccountId(token) : undefined;
    if (!token || !accountId) return;
    const sessionSignal = usageRefreshAbort?.signal;
    const timeoutSignal = AbortSignal.timeout(USAGE_REFRESH_TIMEOUT_MS);
    const signal = sessionSignal ? AbortSignal.any([sessionSignal, timeoutSignal]) : timeoutSignal;
    const response = await fetch(CODEX_USAGE_URL, {
      headers: {
        Accept: 'application/json',
        Authorization: `Bearer ${token}`,
        'ChatGPT-Account-Id': accountId,
        originator: 'pi',
      },
      redirect: 'error',
      signal,
    });
    if (!response.ok) return;
    const parsed = parseCodexUsagePayload((await response.json()) as JsonValue);
    if (!parsed) return;
    currentWindows = { provider: 'openai-codex', ...parsed, capturedAt: Date.now() };
    requestRenderFn?.();
  } catch {
    /* The footer keeps the last valid snapshot when the optional refresh fails. */
  } finally {
    usageRefreshInFlight = false;
  }
}

/* ---------------------------------------------------------------------------
 * Extension entry point
 * --------------------------------------------------------------------------- */

export default function (pi: ExtensionAPI) {
  pi.on('session_start', (_event, ctx) => {
    if (ctx.mode !== 'tui') return;

    usageRefreshAbort?.abort();
    usageRefreshAbort = new AbortController();
    usageLastAttemptAt = 0;
    unsubscribeBranch?.();
    unsubscribeBranch = undefined;

    ctx.ui.setFooter((tui, theme, footerData) => {
      const unsub = footerData.onBranchChange(() => {
        refreshGitDirty(ctx);
        tui.requestRender();
      });
      unsubscribeBranch = unsub;
      requestRenderFn = () => tui.requestRender();
      refreshGitDirty(ctx);

      return {
        invalidate() {},
        dispose() {
          if (unsubscribeBranch === unsub) unsubscribeBranch = undefined;
          unsub();
        },
        render(width: number): string[] {
          requestRenderFn = () => tui.requestRender();

          const spend = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0 };
          for (const entry of ctx.sessionManager.getEntries()) {
            const u =
              entry.type === 'message' && (entry.message.role === 'assistant' || entry.message.role === 'toolResult')
                ? entry.message.usage
                : entry.type === 'branch_summary' || entry.type === 'compaction'
                  ? entry.usage
                  : undefined;
            if (!u) continue;
            spend.input += u.input;
            spend.output += u.output;
            spend.cacheRead += u.cacheRead;
            spend.cacheWrite += u.cacheWrite;
            spend.cost += u.cost.total;
          }

          const spendParts: string[] = [];
          if (spend.input > 0) spendParts.push(`↑${formatTokens(spend.input)}`);
          if (spend.output > 0) spendParts.push(`↓${formatTokens(spend.output)}`);
          if (spend.cacheRead > 0) spendParts.push(`R${formatTokens(spend.cacheRead)}`);
          if (spend.cacheWrite > 0) spendParts.push(`W${formatTokens(spend.cacheWrite)}`);
          if (spend.cost > 0) spendParts.push(`$${spend.cost.toFixed(2)}`);

          const usage = ctx.getContextUsage();
          const context =
            usage && usage.tokens !== null && usage.percent !== null
              ? { tokens: usage.tokens, percent: usage.percent }
              : undefined;

          const live: LiveFooter = {
            cwd: ctx.cwd,
            branch: footerData.getGitBranch(),
            dirty: gitState.dirty,
            spendParts,
            context,
            windows:
              currentWindows && currentWindows.provider === (ctx.model?.provider ?? '')
                ? currentWindows
                : undefined,
            nowSec: Math.floor(Date.now() / 1000),
            modelId: ctx.model?.id,
            thinkingLevel: ctx.thinkingLevel,
          };

          const segs = buildSegs(theme, live);
          return [assembleLine(segs, { theme, width, measure: { visibleWidth, truncateToWidth } })];
        },
      };
    });
    void refreshCodexUsage(ctx);
  });

  pi.on('model_select', (event, ctx) => {
    if (currentWindows && currentWindows.provider !== event.model.provider) {
      /* Windows are provider-scoped; numbers from the old provider must not
       * render next to the new model. */
      currentWindows = undefined;
    }
    if (event.model.provider === 'openai-codex' && event.previousModel?.provider !== 'openai-codex') {
      usageLastAttemptAt = 0;
    }
    // Renders read ctx.model live; this just repaints now.
    requestRenderFn?.();
    void refreshCodexUsage(ctx);
  });

  pi.on('agent_settled', (_event, ctx) => {
    void refreshCodexUsage(ctx);
  });

  pi.on('turn_end', (_event, ctx) => {
    refreshGitDirty(ctx);
    requestRenderFn?.();
  });

  pi.on('tool_execution_end', (_event, ctx) => {
    // Tools may commit or write files mid-turn; recheck drift promptly.
    refreshGitDirty(ctx);
  });

  pi.on('after_provider_response', (event, ctx) => {
    if (!ctx.model) return;
    captureProviderHeaders(event.headers, ctx.model.provider);
    requestRenderFn?.();
  });

  pi.on('session_shutdown', () => {
    usageRefreshAbort?.abort();
    usageRefreshAbort = undefined;
  });
}
