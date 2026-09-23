/**
 * Deny gate: enforces the deny list in settings.json as a PreToolUse hook, so
 * Codex (which has no translation of it) and the shell side of every host get
 * the same rules. Claude Code and Pi keep their native enforcement as well.
 *
 * It blocks a Bash command matching a Bash rule, an edit to a path matching a
 * Read or Edit rule, a shell command naming such a path as an argument, and an
 * MCP tool matching an MCP rule. Naming a path covers reads through cat, grep,
 * cp and the like; it is friction, not a sandbox, because a command can build
 * a path at run time.
 *
 * Rule loading and classification come from the Pi permission gate, so both
 * hosts read the list the same way.
 */

import { readFileSync, realpathSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { type DenyRule, loadGateConfig } from '../../pi/extensions/permission-gate.ts';

export interface HookPayload {
  tool_name?: string;
  tool_input?: { command?: unknown; file_path?: unknown };
  cwd?: string;
}

export interface Verdict {
  rule: string;
  subject: string;
}

function escapeRegex(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/** Command globs: `*` matches any text, as in the dispatcher's `if` matching. */
export function commandGlobMatches(pattern: string, text: string): boolean {
  const source = pattern.split('*').map(escapeRegex).join('.*');
  if (new RegExp(`^${source}$`, 's').test(text)) return true;
  /* `Bash(git push *)` also matches a bare `git push`, like Claude's rules. */
  return pattern.endsWith(' *') && text === pattern.slice(0, -2);
}

/**
 * The whole command plus each top-level segment split on && || ; | and
 * newlines. Quoted text and heredoc bodies are not split, so `ssh host 'sudo x'`
 * stays one command, as it does for Claude's own rules.
 */
export function commandSegments(command: string): string[] {
  const body = stripHeredocs(command);
  const segments: string[] = [command];
  let current = '';
  let quote: '"' | "'" | undefined;
  for (let i = 0; i < body.length; i++) {
    const ch = body[i];
    if (quote !== undefined) {
      if (ch === '\\' && quote === '"' && i + 1 < body.length) current += ch + body[++i];
      else {
        if (ch === quote) quote = undefined;
        current += ch;
      }
      continue;
    }
    if (ch === '\\' && i + 1 < body.length) {
      current += ch + body[++i];
    } else if (ch === "'" || ch === '"') {
      quote = ch;
      current += ch;
    } else if (ch === ';' || ch === '\n' || ch === '|' || (ch === '&' && body[i + 1] === '&')) {
      segments.push(current);
      current = '';
      if ((ch === '|' && body[i + 1] === '|') || ch === '&') i++;
    } else {
      current += ch;
    }
  }
  segments.push(current);
  return segments.map((s) => s.trim()).filter((s) => s.length > 0);
}

/**
 * Path globs in gitignore style: `**` spans directories, `*` stays within one,
 * `~/` is the home directory, and a pattern with no anchor matches at any depth.
 */
export function pathGlobToRegex(pattern: string, home: string = homedir()): RegExp {
  let anchored = pattern;
  let prefix = '';
  if (anchored.startsWith('~/')) {
    prefix = escapeRegex(home.replace(/\/$/, '')) + '/';
    anchored = anchored.slice(2);
  } else if (anchored.startsWith('//')) {
    prefix = '/';
    anchored = anchored.slice(2);
  } else if (anchored.startsWith('/')) {
    prefix = '/';
    anchored = anchored.slice(1);
  } else {
    prefix = '(?:.*/)?';
    if (anchored.startsWith('**/')) anchored = anchored.slice(3);
  }
  let body = '';
  for (let i = 0; i < anchored.length; i++) {
    const ch = anchored[i];
    if (ch === '*' && anchored[i + 1] === '*') {
      if (anchored[i + 2] === '/') {
        body += '(?:.*/)?';
        i += 2;
      } else {
        body += '.*';
        i += 1;
      }
    } else if (ch === '*') body += '[^/]*';
    else if (ch === '?') body += '[^/]';
    else body += escapeRegex(ch);
  }
  return new RegExp(`^${prefix}${body}$`, 's');
}

/** Drop heredoc bodies, so prose piped into a command is not read as paths. */
export function stripHeredocs(command: string): string {
  const lines = command.split('\n');
  const out: string[] = [];
  let terminator: string | undefined;
  for (const line of lines) {
    if (terminator !== undefined) {
      if (line.trim() === terminator) terminator = undefined;
      continue;
    }
    out.push(line);
    const match = /<<-?\s*(['"]?)([A-Za-z_][\w-]*)\1/.exec(line);
    if (match !== null) terminator = match[2];
  }
  return out.join('\n');
}

/** Shell-style words: quotes group, operators and redirections separate. */
export function shellWords(command: string): string[] {
  const words: string[] = [];
  let current = '';
  let quote: '"' | "'" | undefined;
  let started = false;
  const flush = (): void => {
    if (started) words.push(current);
    current = '';
    started = false;
  };
  for (let i = 0; i < command.length; i++) {
    const ch = command[i];
    if (quote !== undefined) {
      if (ch === quote) quote = undefined;
      else if (ch === '\\' && quote === '"' && i + 1 < command.length) current += command[++i];
      else current += ch;
      continue;
    }
    if (ch === "'" || ch === '"') {
      quote = ch;
      started = true;
    } else if (ch === '\\' && i + 1 < command.length) {
      current += command[++i];
      started = true;
    } else if (/\s/.test(ch) || ch === ';' || ch === '|' || ch === '&' || ch === '<' || ch === '>' || ch === '(' || ch === ')') {
      flush();
    } else {
      current += ch;
      started = true;
    }
  }
  flush();
  return words;
}

/** Words that could name a file: not flags, no whitespace, not empty. */
export function candidatePaths(command: string, cwd: string, home: string = homedir()): string[] {
  const paths: string[] = [];
  for (const word of shellWords(stripHeredocs(command))) {
    if (word.length === 0 || word.startsWith('-') || word.includes('=') || /\s/.test(word)) continue;
    let path = word;
    if (path === '~' || path.startsWith('~/')) path = home + path.slice(1);
    else if (path.startsWith('$HOME/')) path = home + path.slice(5);
    else if (path.startsWith('${HOME}/')) path = home + path.slice(7);
    paths.push(isAbsolute(path) ? resolve(path) : resolve(cwd, path));
  }
  return paths;
}

/* Existence and listing checks name a file without reading it. */
const NON_READING = [/^test\s/, /^\[\s/, /^ls(\s|$)/, /^stat\s/, /^git check-ignore\s/];

export interface EvaluateOptions {
  home?: string;
  /* Claude Code and Pi enforce Bash rules natively with their own matching, so
     the gate adds them only where nothing else does. */
  bashRules?: boolean;
}

export function evaluate(payload: HookPayload, rules: DenyRule[], options: EvaluateOptions = {}): Verdict | undefined {
  const home = options.home ?? homedir();
  const tool = payload.tool_name ?? '';
  const cwd = payload.cwd ?? process.cwd();
  const pathRules = rules
    .filter((r) => r.family === 'path-read' || r.family === 'path-write')
    .map((r) => ({ source: r.source, regex: pathGlobToRegex(r.pattern, home) }));
  const matchPath = (path: string): Verdict | undefined => {
    const hit = pathRules.find((r) => r.regex.test(path));
    return hit === undefined ? undefined : { rule: hit.source, subject: path };
  };

  if (tool === 'Bash') {
    const command = typeof payload.tool_input?.command === 'string' ? payload.tool_input.command : '';
    const segments = commandSegments(command);
    if (options.bashRules === true) {
      for (const rule of rules.filter((r) => r.family === 'bash')) {
        if (segments.some((s) => commandGlobMatches(rule.pattern, s))) return { rule: rule.source, subject: command };
      }
    }
    for (const segment of segments.slice(1)) {
      if (NON_READING.some((re) => re.test(segment))) continue;
      for (const path of candidatePaths(segment, cwd, home)) {
        const verdict = matchPath(path);
        if (verdict !== undefined) return verdict;
      }
    }
    return undefined;
  }
  if (tool === 'Edit' || tool === 'Write' || tool === 'Read') {
    const file = payload.tool_input?.file_path;
    if (typeof file !== 'string' || file.length === 0) return undefined;
    return matchPath(isAbsolute(file) ? resolve(file) : resolve(cwd, file));
  }
  if (tool.startsWith('mcp__')) {
    const hit = rules.find((r) => r.family === 'mcp' && commandGlobMatches(r.pattern, tool));
    return hit === undefined ? undefined : { rule: hit.source, subject: tool };
  }
  return undefined;
}

function main(): void {
  const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
  const source = process.env.DENY_RULES_SOURCE ?? join(repoRoot, 'settings.json');
  const config = loadGateConfig(source);
  if (config.status !== 'ok') return;
  let payload: HookPayload;
  try {
    payload = JSON.parse(readFileSync(0, 'utf8')) as HookPayload;
  } catch {
    return;
  }
  const verdict = evaluate(payload, config.rules, { bashRules: process.env.AGENT_HOOK_HOST === 'codex' });
  if (verdict === undefined) return;
  process.stderr.write(`[deny-gate] Blocked by the deny rule ${verdict.rule}: ${verdict.subject}\n`);
  process.stderr.write('The deny list in settings.json forbids this. Find another way or ask the user.\n');
  process.exitCode = 2;
}

/* Hosts reach this file through symlinked hook dirs; compare real paths. */
if (process.argv[1] !== undefined && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) main();
