/**
 * Deny rules: reads the permissions block of settings.json and sorts each deny
 * rule into the family a gate can enforce. The shell deny gate and the Pi
 * permission gate both load the list through this module, so every host reads
 * it the same way.
 *
 * Imports only node builtins, so either host can load it without pi packages.
 */

import { readFileSync } from 'node:fs';

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
