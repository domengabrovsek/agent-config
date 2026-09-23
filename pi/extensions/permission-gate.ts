/**
 * permission-gate - derives pi's permission policy from the harness deny list.
 *
 * The mechanical enforcement itself is the adopted @gotgenes/pi-permission-system
 * package (pinned in pi/settings.json). This extension no longer gates tool
 * calls; it is the translation step that keeps that package's config a Derived
 * policy (CONTEXT.md): regenerated from the permissions block of the tracked
 * root settings.json at every session start, never hand-edited.
 *
 * Translation (deny list -> gotgenes surfaces), deny-only, never "ask":
 *
 *   Read(...)   -> path_read  (cross-cutting: read tool, bash reads, ls/find/grep)
 *   Edit/Write  -> path_write (cross-cutting: write/edit tools, redirects)
 *   Bash(...)   -> bash       (their tree-sitter command enumeration is a
 *                              superset of our old segment matching)
 *   mcp__srv__t -> mcp        (previously a skip notice; now enforced)
 *
 * The universal fallback is "allow": unmatched actions pass, so semantics stay
 * deny-wins/default-allow and headless -p/json/rpc sessions never prompt.
 *
 * Fail loud: a missing, empty, or unparseable permission source leaves the
 * derived config STALE and says so on every session start - error notify plus
 * a persistent widget in TUI, one console.error line in headless modes. The
 * last generated config keeps enforcing; the deny list itself is what lags.
 *
 * Propagation: a deny-list edit reaches the config file during the next
 * session start. The consumer reloads config from disk at session_start with
 * mtime-based cache invalidation, so whichever session_start handler runs
 * first, the change is live no later than the following session.
 *
 * Module top imports only node builtins so `node --test` can exercise the
 * pure helpers without resolving pi packages; the factory resolves
 * @earendil-works/pi-coding-agent dynamically at runtime.
 */

import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';

/* ---------------------------------------------------------------------------
 * Pure rule engine
 * --------------------------------------------------------------------------- */

export type RuleFamily = 'path-read' | 'path-write' | 'bash' | 'mcp';

export interface DenyRule {
  family: RuleFamily;
  /** Pattern inside the Claude rule: a path glob, a command pattern, or an MCP rule id. */
  pattern: string;
  /** Full source rule as written in the deny list, e.g. a Read rule for .env. */
  source: string;
}

export type GateConfig =
  | { status: 'ok'; rules: DenyRule[]; skipped: string[]; allowCount: number }
  | { status: 'missing'; reason: string }
  | { status: 'empty'; reason: string }
  | { status: 'error'; reason: string };

const RULE_RE = /^(Read|Edit|Write|Bash)\((.*)\)$/s;
const MCP_RE = /^mcp__(.+)__([^_]+(?:_[^_]+)*)$/;

/** Classify one Claude permission rule; undefined when pi cannot enforce it. */
export function classifyRule(source: string): { family: RuleFamily; pattern: string } | undefined {
  const trimmed = source.trim();
  const match = RULE_RE.exec(trimmed);
  if (match !== null) {
    const verb = match[1];
    const pattern = match[2];
    if (verb === 'Bash') return { family: 'bash', pattern };
    if (verb === 'Read') return { family: 'path-read', pattern };
    // Edit and Write both bind writes: file-tool rules enforce a superset.
    if (verb === 'Edit' || verb === 'Write') return { family: 'path-write', pattern };
    return undefined;
  }
  if (MCP_RE.test(trimmed)) return { family: 'mcp', pattern: trimmed };
  return undefined;
}

/**
 * Translate a Claude path glob to a gotgenes wildcard pattern. Their `*`
 * crosses `/` (anchored regex with the `s` flag), so collapsing `**` to `*`
 * preserves coverage; a trailing double-star loses only the directory entry itself,
 * which is narrower than the old gate for reads of the bare directory and a
 * superset for everything else (ls/find/grep were never gated before).
 */
export function translatePathPattern(pattern: string): string {
  return pattern.replaceAll('**', '*');
}

/**
 * Translate a Claude MCP rule (`mcp__server__tool`, server may contain single
 * underscores) to a gotgenes mcp-surface pattern. Adjudicated targets cover the
 * bare server name, `server_tool`, and `server:tool` spellings, so a trailing
 * `*` tool matches every spelling.
 */
export function translateMcpRule(source: string): string | undefined {
  const match = MCP_RE.exec(source.trim());
  if (match === null) return undefined;
  const server = match[1];
  const tool = match[2];
  return tool === '*' ? `${server}*` : `${server}:${tool}`;
}

/** State entries keep a deterministic surface map; deny-only maps are order-free. */
export type SurfaceMap = Record<string, 'deny'>;

function denyMap(patterns: string[]): SurfaceMap {
  const map: SurfaceMap = {};
  for (const pattern of [...new Set(patterns)].sort()) map[pattern] = 'deny';
  return map;
}

/**
 * Derive the permission surfaces from classified deny rules. Read rules and
 * Edit rules stay directional (path_read / path_write): their pattern sets are
 * deliberately differ because shell histories and editor storage have Read
 * rules only. A merged `path` surface would block writes absent from the source.
 */
export function derivePermissionPolicy(config: Extract<GateConfig, { status: 'ok' }>): {
  universal: 'allow';
  pathRead: SurfaceMap;
  pathWrite: SurfaceMap;
  bash: SurfaceMap;
  mcp: SurfaceMap;
} {
  const read: string[] = [];
  const write: string[] = [];
  const bash: string[] = [];
  const mcp: string[] = [];
  for (const rule of config.rules) {
    if (rule.family === 'path-read') read.push(translatePathPattern(rule.pattern));
    else if (rule.family === 'path-write') write.push(translatePathPattern(rule.pattern));
    else if (rule.family === 'bash') bash.push(rule.pattern);
    else {
      const pattern = translateMcpRule(rule.pattern);
      if (pattern !== undefined) mcp.push(pattern);
    }
  }
  return {
    universal: 'allow',
    pathRead: denyMap(read),
    pathWrite: denyMap(write),
    bash: denyMap(bash),
    mcp: denyMap(mcp),
  };
}

const PERMISSIONS_SCHEMA_URL =
  'https://raw.githubusercontent.com/gotgenes/pi-packages/main/packages/pi-permission-system/schemas/permissions.schema.json';

/** Assemble the full config document the adopted package validates and loads. */
export function buildPolicyDocument(policy: ReturnType<typeof derivePermissionPolicy>): {
  $schema: string;
  permission: Record<string, unknown>;
} {
  const surfaces: Record<string, unknown> = { '*': policy.universal };
  if (Object.keys(policy.pathRead).length > 0) surfaces.path_read = policy.pathRead;
  if (Object.keys(policy.pathWrite).length > 0) surfaces.path_write = policy.pathWrite;
  /* The package applies the last matching bash rule, so the catch-all goes first
     and every deny after it still wins. Stating it explicitly silences the
     package's warning about bash inheriting the top-level allow. */
  surfaces.bash = { '*': policy.universal, ...policy.bash };
  if (Object.keys(policy.mcp).length > 0) surfaces.mcp = policy.mcp;
  return { $schema: PERMISSIONS_SCHEMA_URL, permission: surfaces };
}

export function serializePolicyDocument(document: ReturnType<typeof buildPolicyDocument>): string {
  return `${JSON.stringify(document, null, 2)}\n`;
}

/** Load and classify the permissions block; never throws. */
export function loadGateConfig(settingsPath: string): GateConfig {
  let parsed: unknown;
  try {
    parsed = JSON.parse(readFileSync(settingsPath, 'utf8'));
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
      return { status: 'missing', reason: `permission source not found: ${settingsPath}` };
    }
    const message = err instanceof Error ? err.message : String(err);
    return { status: 'error', reason: `permission source unreadable: ${message}` };
  }
  if (typeof parsed !== 'object' || parsed === null) {
    return { status: 'empty', reason: 'permission source is not an object' };
  }
  const permissions = (parsed as { permissions?: unknown }).permissions;
  if (typeof permissions !== 'object' || permissions === null) {
    return { status: 'empty', reason: 'no permissions block' };
  }
  const deny = (permissions as { deny?: unknown }).deny;
  if (!Array.isArray(deny) || deny.length === 0) {
    return { status: 'empty', reason: 'deny list absent or empty' };
  }
  const allow = (permissions as { allow?: unknown }).allow;
  const allowCount = Array.isArray(allow) ? allow.length : 0;

  const rules: DenyRule[] = [];
  const skipped: string[] = [];
  for (const source of deny) {
    if (typeof source !== 'string') {
      skipped.push(String(source));
      continue;
    }
    const classified = classifyRule(source);
    if (classified === undefined) {
      skipped.push(source);
      continue;
    }
    rules.push({ ...classified, source });
  }
  if (rules.length === 0) {
    return { status: 'empty', reason: 'deny list translates to zero pi rules' };
  }
  return { status: 'ok', rules, skipped, allowCount };
}

export type SourceSelection =
  | { status: 'ok'; path: string; config: Extract<GateConfig, { status: 'ok' }> }
  | { status: 'unavailable'; reason: string };

/**
 * First candidate that exists and carries a permissions block wins. A parseable
 * settings file without permissions (pi's own settings.json, for instance) is
 * not the permission source and is skipped, not fatal.
 */
export function resolvePermissionSource(candidates: string[]): SourceSelection {
  let unavailableReason: string | undefined;
  for (const candidate of candidates) {
    if (!existsSync(candidate)) continue;
    const config = loadGateConfig(candidate);
    if (config.status === 'ok') return { status: 'ok', path: candidate, config };
    unavailableReason = config.reason;
  }
  if (unavailableReason !== undefined) {
    return { status: 'unavailable', reason: unavailableReason };
  }
  return { status: 'unavailable', reason: 'no permission source found in candidate paths' };
}

/* ---------------------------------------------------------------------------
 * Extension wiring
 * --------------------------------------------------------------------------- */

const WIDGET_ID = 'permission-gate';
const CONSUMER_DIR = 'pi-permission-system';

export default async function (pi: ExtensionAPI) {
  const { getAgentDir } = await import('@earendil-works/pi-coding-agent');

  pi.on('session_start', (_event, ctx) => {
    let moduleDir: string;
    try {
      moduleDir = dirname(realpathSync(fileURLToPath(import.meta.url)));
    } catch {
      moduleDir = dirname(fileURLToPath(import.meta.url));
    }
    /* Order: the tracked root settings.json next to the extension (symlinks
     * resolved, i.e. the checkout), then Claude's config-dir symlink to the
     * same tracked file, then the pi agent dir for standalone installs. */
    const candidates = [
      join(moduleDir, '../../settings.json'),
      join(homedir(), '.claude', 'settings.json'),
      join(getAgentDir(), 'settings.json'),
    ];
    const selection = resolvePermissionSource(candidates);

    const failLoud = (message: string): void => {
      if (ctx.hasUI) {
        ctx.ui.notify(message, 'error');
        ctx.ui.setWidget(WIDGET_ID, ['perms: DERIVED POLICY STALE - deny list not refreshed']);
      } else {
        console.error(message);
      }
    };

    if (selection.status !== 'ok') {
      failLoud(`Derived policy STALE (${selection.reason}); the permission system keeps the last generated config.`);
      return;
    }

    /* Writes go through the agent dir so both account dirs land on the same
     * tracked file via the extensions symlink; it is also the path the
     * consumer resolves (<agent dir>/extensions/pi-permission-system/config.json). */
    const configPath = join(getAgentDir(), 'extensions', CONSUMER_DIR, 'config.json');
    const document = buildPolicyDocument(derivePermissionPolicy(selection.config));
    const serialized = serializePolicyDocument(document);
    let unchanged = false;
    try {
      const existing = existsSync(configPath) ? readFileSync(configPath, 'utf8') : '';
      unchanged = existing === serialized;
      if (!unchanged) {
        mkdirSync(dirname(configPath), { recursive: true });
        writeFileSync(configPath, serialized);
      }
    } catch (err) {
      failLoud(
        `Derived policy could not be written to ${configPath}: ${err instanceof Error ? err.message : String(err)}`,
      );
      return;
    }

    if (ctx.hasUI) ctx.ui.setWidget(WIDGET_ID, undefined);

    const summary = [`derived ${selection.config.rules.length} deny rules from ${selection.path}`];
    if (selection.config.skipped.length > 0) {
      summary.push(`skipped ${selection.config.skipped.length} (no translation): ${selection.config.skipped.join(', ')}`);
    }
    if (selection.config.allowCount > 0) {
      summary.push(`${selection.config.allowCount} allow rules inert (deny-wins)`);
    }
    summary.push(`policy -> ${configPath}${unchanged ? ' (unchanged)' : ''}`);
    if (ctx.hasUI) ctx.ui.notify(`Derived policy: ${summary.join('; ')}`, 'info');
  });
}