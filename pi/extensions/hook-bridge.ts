/**
 * hook-bridge - runs the Claude Code hooks registered in settings.json for pi
 * tool calls and session starts and ends, so every model on pi meets the same
 * gates and session hooks as Claude.
 *
 * Pi adapts, the dispatcher decides: this extension only translates a pi
 * event into the Claude hook payload, invokes hooks/lib/dispatch.sh, and maps
 * the exit code back onto pi's results.
 *
 *   bash             -> Bash   (tool_input.command)
 *   edit/write       -> Edit / Write (tool_input.file_path, absolute)
 *   other tools      -> not dispatched
 *   session_start    -> SessionStart (source startup, resume, or clear)
 *   session_shutdown -> SessionEnd
 *   a reload or a subagent child session dispatches no session event
 *
 * Exit 2 blocks a PreToolUse call and feeds a PostToolUse reason back into
 * the tool result. Exit 0 may carry additionalContext on stdout, which is
 * appended to that call's result. Any other exit, a timeout, or a missing
 * dispatcher is non-blocking: gates fail open with a visible notice. Session
 * hooks never block; their output and failures only become notices.
 *
 * Persona identity: pi-subagents tags a child session's system prompt with
 * an active_agent element naming the agent, which becomes agent_type.
 *
 * Module top imports only node builtins and local modules so `node --test` can
 * exercise the helpers without resolving pi packages.
 */

import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { isAbsolute, join, resolve } from 'node:path';
import type {
  ExtensionAPI,
  ExtensionContext,
  SessionShutdownEvent,
  SessionStartEvent,
} from '@earendil-works/pi-coding-agent';
import { checkoutPath } from './lib/checkout.ts';

export type ToolHookEvent = 'PreToolUse' | 'PostToolUse';
export type HookEvent = ToolHookEvent | 'SessionStart' | 'SessionEnd';
export type ClaudeToolName = 'Bash' | 'Edit' | 'Write';

interface PayloadBase {
  cwd: string;
  session_id?: string;
  agent_type?: string;
}

export interface ToolHookPayload extends PayloadBase {
  hook_event_name: ToolHookEvent;
  tool_name: ClaudeToolName;
  tool_input: { command: string } | { file_path: string };
}

/** Claude's SessionStart sources, which registry matchers select on. */
export type SessionStartSource = 'startup' | 'resume' | 'clear';
/** The Claude SessionEnd reasons a pi shutdown stands for. */
export type SessionEndReason = 'prompt_input_exit' | 'clear' | 'resume' | 'other';

export interface SessionStartPayload extends PayloadBase {
  hook_event_name: 'SessionStart';
  source: SessionStartSource;
}

export interface SessionEndPayload extends PayloadBase {
  hook_event_name: 'SessionEnd';
  reason: SessionEndReason;
}

export type HookPayload = ToolHookPayload | SessionStartPayload | SessionEndPayload;

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
  event: ToolHookEvent;
  piToolName: string;
  input: Record<string, unknown>;
  cwd: string;
  sessionId?: string;
  agentType?: string;
}): ToolHookPayload | undefined {
  const toolName = toClaudeToolName(options.piToolName);
  if (toolName === undefined) return undefined;
  let toolInput: ToolHookPayload['tool_input'];
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

/* A pi reload re-reads extensions and settings inside the same session, so
 * it starts and ends no Claude session. A fork continues an existing
 * transcript, which Claude's --fork-session reports as source "resume". */
const START_SOURCES: Record<SessionStartEvent['reason'], SessionStartSource | undefined> = {
  startup: 'startup',
  resume: 'resume',
  fork: 'resume',
  new: 'clear',
  reload: undefined,
};

const END_REASONS: Record<SessionShutdownEvent['reason'], SessionEndReason | undefined> = {
  quit: 'prompt_input_exit',
  new: 'clear',
  resume: 'resume',
  fork: 'other',
  reload: undefined,
};

interface SessionPayloadOptions {
  cwd: string;
  sessionId?: string;
  agentType?: string;
}

/* Claude fires no session events for subagents, so a pi-subagents child,
 * which carries an agent type, dispatches none either. */
function sessionBase(options: SessionPayloadOptions): PayloadBase | undefined {
  if (options.agentType !== undefined) return undefined;
  return { cwd: options.cwd, ...(options.sessionId ? { session_id: options.sessionId } : {}) };
}

/** Build the SessionStart payload; undefined for a reload or a subagent child. */
export function buildSessionStartPayload(
  options: SessionPayloadOptions & { reason: SessionStartEvent['reason'] },
): SessionStartPayload | undefined {
  const source = START_SOURCES[options.reason];
  const base = sessionBase(options);
  if (source === undefined || base === undefined) return undefined;
  return { hook_event_name: 'SessionStart', source, ...base };
}

/** Build the SessionEnd payload; undefined for a reload or a subagent child. */
export function buildSessionEndPayload(
  options: SessionPayloadOptions & { reason: SessionShutdownEvent['reason'] },
): SessionEndPayload | undefined {
  const reason = END_REASONS[options.reason];
  const base = sessionBase(options);
  if (reason === undefined || base === undefined) return undefined;
  return { hook_event_name: 'SessionEnd', reason, ...base };
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
      env: { ...process.env, AGENT_HOOK_HOST: 'pi' },
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

/* Pi calls every extension factory again for the runtime that replaces a
   session on reload, new, resume, or fork, in the same process. The session
   being torn down releases its claim so that runtime registers the bridge. */
export function releaseBridge(scope: Record<symbol, unknown> = globalThis as Record<symbol, unknown>): void {
  scope[LOADED] = false;
}

export default function (pi: ExtensionAPI) {
  if (!claimBridge()) return;
  const dispatcherPath = checkoutPath(import.meta.url, 'hooks/lib/dispatch.sh');
  const pendingNotes = new Map<string, string[]>();
  let missingReported = false;

  const warn = (ctx: ExtensionContext, message: string): void => {
    if (ctx.hasUI) ctx.ui.notify(message, 'warning');
    else console.error(message);
  };

  const send = async (ctx: ExtensionContext, payload: HookPayload | undefined): Promise<DispatchOutcome | undefined> => {
    if (payload === undefined) return undefined;
    if (!existsSync(dispatcherPath)) {
      if (!missingReported) {
        missingReported = true;
        warn(ctx, `Hook bridge inactive: ${dispatcherPath} not found. Pi runs without Claude hooks.`);
      }
      return undefined;
    }
    const event = payload.hook_event_name;
    const outcome = interpretDispatch(event, await runDispatcher(dispatcherPath, event, payload, { cwd: ctx.cwd }));
    if (outcome.kind === 'pass' && outcome.notice !== undefined) warn(ctx, outcome.notice);
    return outcome;
  };

  const dispatchTool = (
    ctx: ExtensionContext,
    event: ToolHookEvent,
    piToolName: string,
    input: Record<string, unknown>,
  ): Promise<DispatchOutcome | undefined> =>
    send(ctx, buildHookPayload({ event, piToolName, input, cwd: ctx.cwd, sessionId: sessionIdOf(ctx), agentType: agentTypeOf(ctx) }));

  /* Session hooks cannot block pi: a blocking exit becomes a warning. Pi has
   * no session-start slot in the model's context, so printed context goes to
   * the user instead. */
  const reportSession = (ctx: ExtensionContext, outcome: DispatchOutcome | undefined): void => {
    if (outcome?.kind === 'block') warn(ctx, outcome.reason);
    else if (outcome?.context !== undefined && ctx.hasUI) ctx.ui.notify(outcome.context, 'info');
  };

  pi.on('session_start', async (event, ctx) => {
    const payload = buildSessionStartPayload({ reason: event.reason, cwd: ctx.cwd, sessionId: sessionIdOf(ctx), agentType: agentTypeOf(ctx) });
    reportSession(ctx, await send(ctx, payload));
  });

  pi.on('session_shutdown', async (event, ctx) => {
    releaseBridge();
    const payload = buildSessionEndPayload({ reason: event.reason, cwd: ctx.cwd, sessionId: sessionIdOf(ctx), agentType: agentTypeOf(ctx) });
    reportSession(ctx, await send(ctx, payload));
  });

  pi.on('tool_call', async (event, ctx) => {
    const outcome = await dispatchTool(ctx, 'PreToolUse', event.toolName, event.input as Record<string, unknown>);
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
      const outcome = await dispatchTool(ctx, 'PostToolUse', event.toolName, event.input);
      if (outcome?.kind === 'block') notes.push(`PostToolUse hook feedback:\n${outcome.reason}`);
      else if (outcome?.context !== undefined) notes.push(outcome.context);
    }
    if (notes.length === 0) return undefined;
    return { content: appendText(event.content, notes.join('\n\n')) };
  });
}
