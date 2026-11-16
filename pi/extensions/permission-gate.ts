/**
 * permission-gate - derives pi's permission policy from the harness deny list.
 *
 * The mechanical enforcement itself is the adopted @gotgenes/pi-permission-system
 * package (pinned in pi/settings.json). This extension is the translation step
 * that keeps that package's config a Derived policy (CONTEXT.md): regenerated
 * from the permissions block of the tracked root settings.json at every
 * session start, never hand-edited.
 *
 * Translation (deny list -> gotgenes surfaces), deny-only, never "ask":
 *
 *   Read(...)   -> path_read  (cross-cutting: read tool, bash reads, ls/find/grep)
 *   Edit/Write  -> path_write (cross-cutting: write/edit tools, redirects)
 *   Bash(...)   -> bash       (tree-sitter command enumeration)
 *   mcp__srv__t -> mcp
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
 * @earendil-works/pi-coding-agent and the shared rule loader in
 * hooks/lib/deny-rules.ts dynamically at runtime.
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';
import type { GateConfig } from '../../hooks/lib/deny-rules.ts';
import { checkoutPath } from './lib/checkout.ts';

type DenyRulesModule = typeof import('../../hooks/lib/deny-rules.ts');

/* ---------------------------------------------------------------------------
 * Pure rule engine
 * --------------------------------------------------------------------------- */

/* Same shape as the classifier's MCP pattern in deny-rules.ts, split into server and tool. */
const MCP_RE = /^mcp__(.+)__([^_]+(?:_[^_]+)*)$/;

/**
 * Translate a Claude path glob to a gotgenes wildcard pattern. Their `*`
 * crosses `/` (anchored regex with the `s` flag), so collapsing `**` to `*`
 * preserves coverage; a trailing double-star loses only the directory entry
 * itself.
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
  const surfaces: Record<string, unknown> = { '*': 'allow' };
  if (Object.keys(policy.pathRead).length > 0) surfaces.path_read = policy.pathRead;
  if (Object.keys(policy.pathWrite).length > 0) surfaces.path_write = policy.pathWrite;
  /* The package applies the last matching bash rule, so the catch-all goes first
     and every deny after it still wins. Stating it explicitly silences the
     package's warning about bash inheriting the top-level allow. */
  surfaces.bash = { '*': 'allow', ...policy.bash };
  if (Object.keys(policy.mcp).length > 0) surfaces.mcp = policy.mcp;
  return { $schema: PERMISSIONS_SCHEMA_URL, permission: surfaces };
}

export function serializePolicyDocument(document: ReturnType<typeof buildPolicyDocument>): string {
  return `${JSON.stringify(document, null, 2)}\n`;
}

/* ---------------------------------------------------------------------------
 * Extension wiring
 * --------------------------------------------------------------------------- */

const WIDGET_ID = 'permission-gate';
const CONSUMER_DIR = 'pi-permission-system';

export default async function (pi: ExtensionAPI) {
  const { getAgentDir } = await import('@earendil-works/pi-coding-agent');
  /* Pi loads the module by its symlinked path and does not resolve it, so a
   * static import of hooks/lib would miss the checkout. */
  const { loadGateConfig }: DenyRulesModule = await import(
    pathToFileURL(checkoutPath(import.meta.url, 'hooks/lib/deny-rules.ts')).href
  );

  pi.on('session_start', (_event, ctx) => {
    const sourcePath = checkoutPath(import.meta.url, 'settings.json');
    const config = loadGateConfig(sourcePath);

    const failLoud = (message: string): void => {
      if (ctx.hasUI) {
        ctx.ui.notify(message, 'error');
        ctx.ui.setWidget(WIDGET_ID, ['perms: DERIVED POLICY STALE - deny list not refreshed']);
      } else {
        console.error(message);
      }
    };

    if (config.status !== 'ok') {
      failLoud(`Derived policy STALE (${config.reason}); the permission system keeps the last generated config.`);
      return;
    }

    /* Writes go through the agent dir so both account dirs land on the same
     * tracked file via the extensions symlink; it is also the path the
     * consumer resolves (<agent dir>/extensions/pi-permission-system/config.json). */
    const configPath = join(getAgentDir(), 'extensions', CONSUMER_DIR, 'config.json');
    const serialized = serializePolicyDocument(buildPolicyDocument(derivePermissionPolicy(config)));
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

    const summary = [`derived ${config.rules.length} deny rules from ${sourcePath}`];
    if (config.skipped.length > 0) {
      summary.push(`skipped ${config.skipped.length} (no translation): ${config.skipped.join(', ')}`);
    }
    if (config.allowCount > 0) {
      summary.push(`${config.allowCount} allow rules inert (deny-wins)`);
    }
    summary.push(`policy -> ${configPath}${unchanged ? ' (unchanged)' : ''}`);
    if (ctx.hasUI) ctx.ui.notify(`Derived policy: ${summary.join('; ')}`, 'info');
  });
}