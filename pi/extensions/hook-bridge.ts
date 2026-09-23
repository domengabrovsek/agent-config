/**
 * hook-bridge - runs the Claude Code hooks registered in settings.json for pi
 * tool calls, so every model on pi meets the same gates as Claude.
 *
 * Pi adapts, the dispatcher decides: this extension only translates a pi tool
 * call into the Claude hook payload, invokes hooks/lib/dispatch.sh, and maps
 * the exit code back onto pi's tool_call / tool_result results.
 *
 *   bash        -> Bash   (tool_input.command)
 *   edit/write  -> Edit / Write (tool_input.file_path, absolute)
 *   anything else is not dispatched
 *
 * Exit 2 blocks a PreToolUse call and feeds a PostToolUse reason back into
 * the tool result. Exit 0 may carry additionalContext on stdout, which is
 * appended to that call's result. Any other exit, a timeout, or a missing
 * dispatcher is non-blocking: gates fail open with a visible notice.
 *
 * Persona identity: pi-subagents tags a child session's system prompt with
 * an active_agent element naming the agent, which becomes agent_type.
 *
 * Module top imports only node builtins so `node --test` can exercise the
 * helpers without resolving pi packages.
 */

import { spawn } from 'node:child_process';
import { existsSync, realpathSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { ExtensionAPI, ExtensionContext } from '@earendil-works/pi-coding-agent';

export type HookEvent = 'PreToolUse' | 'PostToolUse';
export type ClaudeToolName = 'Bash' | 'Edit' | 'Write';

export interface HookPayload {
  hook_event_name: HookEvent;
  tool_name: ClaudeToolName;
  tool_input: { command: string } | { file_path: string };
  cwd: string;
  session_id?: string;
  agent_type?: string;
}

const TOOL_NAMES: Record<string, ClaudeToolName> = { bash: 'Bash', edit: 'Edit', write: 'Write' };

export function toClaudeToolName(piToolName: string): ClaudeToolName | undefined {
  return Object.hasOwn(TOOL_NAMES, piToolName) ? TOOL_NAMES[piToolName] : undefined;
}

/** Mirror pi's resolveToCwd: strip the `@` mention prefix, expand `~`, resolve against cwd. */
export function resolvePiPath(path: string, cwd: string, home: string = homedir()): string {
  const bare = path.startsWith('@') ? path.slice(1) : path;
  if (bare === '~') return home;
  if (bare.startsWith('~/')) return join(home, bare.slice(2));
  return isAbsolute(bare) ? resolve(bare) : resolve(cwd, bare);
}

/** Build the Claude-shaped hook payload; undefined for tools the hooks never see. */
export function buildHookPayload(options: {
  event: HookEvent;
  piToolName: string;
  input: Record<string, unknown>;
  cwd: string;
  sessionId?: string;
  agentType?: string;
}): HookPayload | undefined {
  const toolName = toClaudeToolName(options.piToolName);
  if (toolName === undefined) return undefined;
  let toolInput: HookPayload['tool_input'];
  if (toolName === 'Bash') {
    const command = options.input.command;
    if (typeof command !== 'string') return undefined;
    toolInput = { command };
  } else {
    const path = options.input.path;
    if (typeof path !== 'string' || path.length === 0) return undefined;
    toolInput = { file_path: resolvePiPath(path, options.cwd) };
  }
  return {
    hook_event_name: options.event,
    tool_name: toolName,
    tool_input: toolInput,
    cwd: options.cwd,
    ...(options.sessionId ? { session_id: options.sessionId } : {}),
    ...(options.agentType ? { agent_type: options.agentType } : {}),
  };
}

const ACTIVE_AGENT_RE = /<active_agent name="((?:[^"\\]|\\.)*)"\s*\/>/;

/**
 * Read the agent name pi-subagents writes into a child's system prompt. It
 * escapes the name as an XML attribute on one path and as a JSON string on
 * another, so both escape styles are decoded.
 */
export function parseActiveAgent(systemPrompt: string): string | undefined {
  const match = ACTIVE_AGENT_RE.exec(systemPrompt);
  if (match === null) return undefined;
  const name = match[1]
    .replace(/\\(["\\])/g, '$1')
    .replaceAll('&quot;', '"')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&')
    .trim();
  return name.length > 0 ? name : undefined;
}

export interface DispatchResult {
  code: number | null;
  stdout: string;
  stderr: string;
  timedOut: boolean;
}

export type DispatchOutcome =
  | { kind: 'block'; reason: string }
  | { kind: 'pass'; context?: string; notice?: string };

/** Map a dispatcher run onto block / pass. Only exit 2 blocks, even after a timeout. */
export function interpretDispatch(event: HookEvent, result: DispatchResult): DispatchOutcome {
  if (result.code === 2) {
    const reason = result.stderr.trim();
    return { kind: 'block', reason: reason.length > 0 ? reason : `${event} hook blocked this call without a reason.` };
  }
  if (result.timedOut) {
    return { kind: 'pass', notice: `${event} hooks timed out; the call proceeded without their verdict.` };
  }
  if (result.code !== 0) {
    const detail = result.stderr.trim();
    return {
      kind: 'pass',
      notice: `${event} hooks failed (exit ${result.code ?? 'signal'}), non-blocking${detail ? `: ${detail}` : '.'}`,
    };
  }
  return { kind: 'pass', ...(extractAdditionalContext(result.stdout) ?? {}) };
}

function extractAdditionalContext(stdout: string): { context: string } | undefined {
  const trimmed = stdout.trim();
  if (trimmed.length === 0) return undefined;
  try {
    const parsed: unknown = JSON.parse(trimmed);
    const output = (parsed as { hookSpecificOutput?: { additionalContext?: unknown } })?.hookSpecificOutput;
    const context = output?.additionalContext;
    return typeof context === 'string' && context.trim().length > 0 ? { context: context.trim() } : undefined;
  } catch {
    return undefined;
  }
}

/** Resolve dispatch.sh from this module's real path: extension dirs are symlinks into the checkout. */
export function resolveDispatcherPath(moduleUrl: string): string {
  const modulePath = fileURLToPath(moduleUrl);
  let moduleDir: string;
  try {
    moduleDir = dirname(realpathSync(modulePath));
  } catch {
    moduleDir = dirname(modulePath);
  }
  return join(moduleDir, '../../hooks/lib/dispatch.sh');
}

/* Above the largest per-hook timeout in settings.json (pre-push-gate, 300s), so the
 * dispatcher's own per-hook bound fires first and a slow push gate is not cut
 * off into a fail-open by this outer bound. */
export const DISPATCH_TIMEOUT_MS = 330_000;
const MAX_CAPTURE_BYTES = 1024 * 1024;

/** Run the dispatcher with the payload on stdin; never rejects. */
export function runDispatcher(
  dispatcherPath: string,
  event: HookEvent,
  payload: HookPayload,
  options: { cwd: string; timeoutMs?: number } = { cwd: process.cwd() },
): Promise<DispatchResult> {
  return new Promise((resolveRun) => {
    let stdout = '';
    let stderr = '';
    let timedOut = false;
    let settled = false;
    const finish = (result: DispatchResult): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolveRun(result);
    };

    /* Its own process group, so a timeout kills the hooks the dispatcher
     * started too, not only the bash wrapper. */
    const child = spawn('bash', [dispatcherPath, event], {
      cwd: options.cwd,
      detached: true,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    const timer = setTimeout(() => {
      timedOut = true;
      try {
        if (child.pid !== undefined) process.kill(-child.pid, 'SIGKILL');
      } catch {
        child.kill('SIGKILL');
      }
    }, options.timeoutMs ?? DISPATCH_TIMEOUT_MS);

    child.stdout.on('data', (chunk: Buffer) => {
      if (stdout.length < MAX_CAPTURE_BYTES) stdout += chunk.toString('utf8');
    });
    child.stderr.on('data', (chunk: Buffer) => {
      if (stderr.length < MAX_CAPTURE_BYTES) stderr += chunk.toString('utf8');
    });
    child.on('error', (error) => finish({ code: null, stdout, stderr: stderr || error.message, timedOut }));
    child.on('close', (code) => finish({ code, stdout, stderr, timedOut }));
    /* A hook that backgrounds a process holding our stdout keeps 'close' from
     * firing, so the exit code wins after a short drain window. */
    child.on('exit', (code) => {
      setTimeout(() => finish({ code, stdout, stderr, timedOut }), 1000).unref();
    });
    // A dispatcher that exits before reading stdin raises EPIPE here; its exit code still decides.
    child.stdin.on('error', () => {});
    child.stdin.end(JSON.stringify(payload));
  });
}

export function appendText<T>(content: T[], text: string): (T | { type: 'text'; text: string })[] {
  return [...content, { type: 'text', text }];
}

function agentTypeOf(ctx: ExtensionContext): string | undefined {
  try {
    return parseActiveAgent(ctx.getSystemPrompt());
  } catch {
    return undefined;
  }
}

function sessionIdOf(ctx: ExtensionContext): string | undefined {
  try {
    return ctx.sessionManager.getSessionId();
  } catch {
    return undefined;
  }
}

const LOADED = Symbol.for('agent-config.hook-bridge.loaded');

/* A background subagent child can load this file twice: once from the linked
   extensions dir and once from subagents.defaultSubagentOnlyExtensions. A second
   registration would run every hook twice, so only the first one registers. */
export function claimBridge(scope: Record<symbol, unknown> = globalThis as Record<symbol, unknown>): boolean {
  if (scope[LOADED]) return false;
  scope[LOADED] = true;
  return true;
}

export default function (pi: ExtensionAPI) {
  if (!claimBridge()) return;
  const dispatcherPath = resolveDispatcherPath(import.meta.url);
  const pendingNotes = new Map<string, string[]>();
  let missingReported = false;

  const warn = (ctx: ExtensionContext, message: string): void => {
    if (ctx.hasUI) ctx.ui.notify(message, 'warning');
    else console.error(message);
  };

  const dispatch = async (
    ctx: ExtensionContext,
    event: HookEvent,
    piToolName: string,
    input: Record<string, unknown>,
  ): Promise<DispatchOutcome | undefined> => {
    const payload = buildHookPayload({
      event,
      piToolName,
      input,
      cwd: ctx.cwd,
      sessionId: sessionIdOf(ctx),
      agentType: agentTypeOf(ctx),
    });
    if (payload === undefined) return undefined;
    if (!existsSync(dispatcherPath)) {
      if (!missingReported) {
        missingReported = true;
        warn(ctx, `Hook bridge inactive: ${dispatcherPath} not found. Tool calls run without Claude hooks.`);
      }
      return undefined;
    }
    const outcome = interpretDispatch(event, await runDispatcher(dispatcherPath, event, payload, { cwd: ctx.cwd }));
    if (outcome.kind === 'pass' && outcome.notice !== undefined) warn(ctx, outcome.notice);
    return outcome;
  };

  pi.on('tool_call', async (event, ctx) => {
    const outcome = await dispatch(ctx, 'PreToolUse', event.toolName, event.input as Record<string, unknown>);
    if (outcome === undefined) return undefined;
    if (outcome.kind === 'block') return { block: true, reason: outcome.reason };
    if (outcome.context !== undefined) pendingNotes.set(event.toolCallId, [outcome.context]);
    return undefined;
  });

  pi.on('tool_result', async (event, ctx) => {
    const notes = pendingNotes.get(event.toolCallId) ?? [];
    pendingNotes.delete(event.toolCallId);
    // Claude runs PostToolUse only after a successful call; failures and blocked calls skip it.
    if (!event.isError) {
      const outcome = await dispatch(ctx, 'PostToolUse', event.toolName, event.input);
      if (outcome?.kind === 'block') notes.push(`PostToolUse hook feedback:\n${outcome.reason}`);
      else if (outcome?.context !== undefined) notes.push(outcome.context);
    }
    if (notes.length === 0) return undefined;
    return { content: appendText(event.content, notes.join('\n\n')) };
  });
}
