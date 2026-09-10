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
 * Portability: imports only the adjacent parser, pi packages, and node builtins.
 *
 * Approved plan: .claude/state/plans/2026-08-31-pi-statusline-footer.md
 */

import { execFile } from "node:child_process";
import { basename } from "node:path";

import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
	extractOpenAIAccountId,
	parseCodexHeaders,
	parseCodexUsagePayload,
	type JsonValue,
	type UsageWindow,
} from "./statusline/usage.ts";

export type { UsageWindow } from "./statusline/usage.ts";

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

type ColorToken = "success" | "warning" | "error" | "dim" | "accent";

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
	if (seconds <= 0) return "";
	if (seconds < 60) return "<1m";
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
		rejected: REJECTED_STATUS.test(rawStatus ?? ""),
	};
};

/** Parse anthropic-ratelimit-unified-* headers (utilization is a 0..1 float). */
export function parseUnifiedHeaders(
	headers: Record<string, string>,
): Pick<UsageWindows, "fiveHour" | "sevenDay"> | undefined {
	const fiveHour = windowFrom(
		num(headers["anthropic-ratelimit-unified-5h-utilization"]),
		num(headers["anthropic-ratelimit-unified-5h-reset"]),
		headers["anthropic-ratelimit-unified-5h-status"],
	);
	const sevenDay = windowFrom(
		num(headers["anthropic-ratelimit-unified-7d-utilization"]),
		num(headers["anthropic-ratelimit-unified-7d-reset"]),
		headers["anthropic-ratelimit-unified-7d-status"],
	);
	return fiveHour || sevenDay ? { fiveHour, sevenDay } : undefined;
}

/** Green/yellow/red at the statusline's 50%/80% thresholds. */
export function usageColorName(pct: number, binding: boolean): ColorToken {
	if (binding) return "error";
	if (pct >= 80) return "error";
	if (pct >= 50) return "warning";
	return "success";
}

// ---------------------------------------------------------------------------
// Line assembly
// ---------------------------------------------------------------------------

const SEP = " │ ";

interface Seg {
	text: string;
	/**
	 * Drop priority: segments drop right-to-left (model=1, usage=2, spend=3)
	 * under width pressure; segments without a priority are never dropped.
	 */
	drop?: 1 | 2 | 3;
}

export interface LiveFooterState {
	cwd: string;
	branch: string | null;
	dirty: boolean | undefined;
	spendParts: string[];
	/** `145k (34%)` data, or undefined before the first response. */
	context: { tokens: number; percent: number } | undefined;
	windows: UsageWindows | undefined;
	nowSec: number;
	modelId: string | undefined;
	thinkingLevel?: string;
}

function usageSegments(
	theme: FooterStyle,
	windows: UsageWindows,
	nowSec: number,
): Seg[] | undefined {
	const ageSec = nowSec - Math.floor(windows.capturedAt / 1000);
	if (ageSec >= 3600) return undefined; // too stale to be honest
	const parts: string[] = [];
	for (const [win, fallbackLabel] of [
		[windows.fiveHour, "5h"],
		[windows.sevenDay, "7d"],
	] as const) {
		if (!win) continue;
		const label = win.label ?? fallbackLabel;
		const color: ColorToken = ageSec >= 600 ? "dim" : usageColorName(win.pct ?? 0, win.rejected);
		const resetSuffix =
			win.resetEpochSec !== null && win.resetEpochSec > nowSec
				? ` ${theme.fg("dim", `(${humanizeReset(win.resetEpochSec - nowSec)})`)}`
				: "";
		parts.push(`${theme.fg(color, `${label} ${win.pct ?? 0}%`)}${resetSuffix}`);
	}
	return parts.length > 0 ? [{ text: parts.join(" "), drop: 2 }] : undefined;
}

/**
 * Build the footer segments in display order. Context and branch stay until the
 * line runs out of width; model, usage windows, and spend drop in that order.
 */
export function buildSegs(theme: FooterStyle, live: Omit<LiveFooter, "windows"> & { windows?: UsageWindows }): Seg[] {
	const segs: Seg[] = [];

	segs.push({ text: theme.bold(basename(live.cwd)) });

	if (live.branch) {
		const dirty = live.dirty === true;
		const color: ColorToken = live.branch === "detached" ? "dim" : dirty ? "error" : "success";
		segs.push({ text: `${theme.fg("dim", "on")} ${theme.fg(color, `${live.branch}${dirty ? "*" : ""}`)}` });
	}

	if (live.spendParts.length > 0) segs.push({ text: theme.fg("dim", live.spendParts.join(" ")), drop: 3 });

	if (live.context) {
		const pct = Math.round(live.context.percent);
		segs.push({
			text: `${theme.fg("accent", "context")} ${theme.fg(usageColorName(pct, false), `${formatTokens(live.context.tokens)} (${pct}%)`)}`,
		});
	} else {
		segs.push({ text: `${theme.fg("accent", "context")} ${theme.fg("dim", "-")}` });
	}

	if (live.windows) {
		const segs5 = usageSegments(theme, live.windows, live.nowSec);
		if (segs5) segs.push(...segs5);
	}

	if (live.modelId) {
		segs.push({
			text: theme.fg("dim", live.thinkingLevel ? `${live.modelId} · ${live.thinkingLevel}` : live.modelId),
			drop: 1,
		});
	}

	return segs;
}

/** Drop by drop-priority (1=model, 2=usage, 3=spend) until the line fits, then hard-truncate. */
export function assembleLine(theme: FooterStyle, segs: Seg[], width: number): string {
	const sep = theme.fg("dim", SEP);
	const join = (pool: Seg[]): string => pool.map((s) => s.text).join(sep);
	let pool = [...segs];
	let line = join(pool);
	while (visibleWidth(line) > width && pool.length > 1) {
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
	return truncateToWidth(line, width);
}

// ---------------------------------------------------------------------------
// Live state
// ---------------------------------------------------------------------------

interface LiveFooter {
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

let requestRenderFn: (() => void) | undefined;
let currentWindows: UsageWindows | undefined;
let unsubscribeBranch: (() => void) | undefined;
let usageRefreshAbort: AbortController | undefined;
let usageRefreshInFlight = false;
let usageLastAttemptAt = 0;

const DIRTY_TTL_MS = 60_000;
const USAGE_REFRESH_TTL_MS = 60_000;
const USAGE_REFRESH_TIMEOUT_MS = 5_000;
const CODEX_USAGE_URL = "https://chatgpt.com/backend-api/wham/usage";
const gitState = {
	dirty: undefined as boolean | undefined,
	checkedAt: 0,
	inFlight: false,
	cwd: "",
};

function refreshGitDirty(ctx: { cwd: string }): void {
	if (gitState.inFlight) return;
	const now = Date.now();
	if (gitState.cwd === ctx.cwd && now - gitState.checkedAt < DIRTY_TTL_MS) return;
	gitState.inFlight = true;
	gitState.cwd = ctx.cwd;
	execFile(
		"git",
		["-C", ctx.cwd, "-c", "core.hooksPath=/dev/null", "status", "--porcelain"],
		{ cwd: ctx.cwd, timeout: 4000 },
		(err, stdout) => {
			gitState.inFlight = false;
			gitState.checkedAt = now;
			// No repo / empty repo / git broken: never show a dirty marker.
			gitState.dirty = err ? false : stdout.split("\n").some((line) => line.trim().length > 0);
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
	if (ctx.model?.provider !== "openai-codex" || usageRefreshInFlight) return;
	const now = Date.now();
	if (now - usageLastAttemptAt < USAGE_REFRESH_TTL_MS) return;
	usageLastAttemptAt = now;
	usageRefreshInFlight = true;

	try {
		const resolved = await ctx.modelRegistry.getProviderAuth("openai-codex");
		const token = resolved?.auth.apiKey;
		const accountId = token ? extractOpenAIAccountId(token) : undefined;
		if (!token || !accountId) return;
		const sessionSignal = usageRefreshAbort?.signal;
		const timeoutSignal = AbortSignal.timeout(USAGE_REFRESH_TIMEOUT_MS);
		const signal = sessionSignal ? AbortSignal.any([sessionSignal, timeoutSignal]) : timeoutSignal;
		const response = await fetch(CODEX_USAGE_URL, {
			headers: {
				Accept: "application/json",
				Authorization: `Bearer ${token}`,
				"ChatGPT-Account-Id": accountId,
				originator: "pi",
			},
			redirect: "error",
			signal,
		});
		if (!response.ok) return;
		const parsed = parseCodexUsagePayload((await response.json()) as JsonValue);
		if (!parsed) return;
		currentWindows = { provider: "openai-codex", ...parsed, capturedAt: Date.now() };
		requestRenderFn?.();
	} catch {
		/* The footer keeps the last valid snapshot when the optional refresh fails. */
	} finally {
		usageRefreshInFlight = false;
	}
}

// ---------------------------------------------------------------------------
// Extension entry point
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		if (ctx.mode !== "tui") return;

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
						if (entry.type === "message" && entry.message.role === "assistant") {
							const u = entry.message.usage;
							spend.input += u.input;
							spend.output += u.output;
							spend.cacheRead += u.cacheRead;
							spend.cacheWrite += u.cacheWrite;
							spend.cost += u.cost.total;
						} else if (entry.type === "message" && entry.message.role === "toolResult" && entry.message.usage) {
							const u = entry.message.usage;
							spend.input += u.input;
							spend.output += u.output;
							spend.cacheRead += u.cacheRead;
							spend.cacheWrite += u.cacheWrite;
							spend.cost += u.cost.total;
						} else if ((entry.type === "branch_summary" || entry.type === "compaction") && entry.usage) {
							const u = entry.usage;
							spend.input += u.input;
							spend.output += u.output;
							spend.cacheRead += u.cacheRead;
							spend.cacheWrite += u.cacheWrite;
							spend.cost += u.cost.total;
						}
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
							currentWindows && currentWindows.provider === (ctx.model?.provider ?? "")
								? currentWindows
								: undefined,
						nowSec: Math.floor(Date.now() / 1000),
						modelId: ctx.model?.id,
						thinkingLevel: ctx.thinkingLevel,
					};

					const segs = buildSegs(theme, live);
					return [assembleLine({ fg: (t, s) => theme.fg(t, s), bold: (s) => theme.bold(s) }, segs, width)];
				},
			};
		});
		void refreshCodexUsage(ctx);
	});

	pi.on("model_select", (event, ctx) => {
		if (currentWindows && currentWindows.provider !== event.model.provider) {
			// Windows are provider-scoped; numbers from the old provider must not
			// render next to the new model.
			currentWindows = undefined;
		}
		if (event.model.provider === "openai-codex" && event.previousModel?.provider !== "openai-codex") {
			usageLastAttemptAt = 0;
		}
		// Renders read ctx.model live; this just repaints now.
		requestRenderFn?.();
		void refreshCodexUsage(ctx);
	});

	pi.on("agent_settled", (_event, ctx) => {
		void refreshCodexUsage(ctx);
	});

	pi.on("turn_end", (_event, ctx) => {
		refreshGitDirty(ctx);
		requestRenderFn?.();
	});

	pi.on("tool_execution_end", (_event, ctx) => {
		// Tools may commit or write files mid-turn; recheck drift promptly.
		refreshGitDirty(ctx);
	});

	pi.on("after_provider_response", (event, ctx) => {
		if (!ctx.model) return;
		captureProviderHeaders(event.headers, ctx.model.provider);
		requestRenderFn?.();
	});

	pi.on("session_shutdown", () => {
		usageRefreshAbort?.abort();
		usageRefreshAbort = undefined;
	});
}
