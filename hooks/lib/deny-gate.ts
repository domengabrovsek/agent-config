/**
 * Deny gate: enforces the deny list in settings.json as a PreToolUse hook, so
 * Codex (which has no translation of it) and the shell side of every host get
 * the same rules. Claude Code and Pi keep their native enforcement as well.
 *
 * Bash rules apply on every host, because native matching reads the command
 * literally and misses wrapped, reordered, and refspec forms of a denied one.
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

/* Wrappers that take options before the command, with the options whose value is the next word. */
const OPTION_WRAPPERS = new Map<string, Set<string>>([
  ['command', new Set()],
  ['builtin', new Set()],
  ['exec', new Set(['-a'])],
  ['env', new Set(['-u', '--unset', '-C', '--chdir', '-S', '--split-string'])],
  ['time', new Set(['-f', '--format', '-o', '--output'])],
  ['nice', new Set(['-n', '--adjustment'])],
  ['nohup', new Set()],
  ['timeout', new Set(['-s', '--signal', '-k', '--kill-after'])],
]);

/* `/usr/bin/env` runs as `env`; a word ending in `/` is a directory, not a program. */
function programName(word: string): string {
  return word.includes('/') && !word.endsWith('/') ? word.slice(word.lastIndexOf('/') + 1) : word;
}
const ASSIGNMENT = /^[A-Za-z_][A-Za-z0-9_]*=/;
/* Git global options that take the next word as their value unless written with `=`. */
const GIT_VALUE_OPTIONS = new Set(['-C', '-c', '--git-dir', '--work-tree', '--namespace', '--config-env', '--exec-path', '--attr-source']);

/**
 * The words a segment runs, with what changes nothing about the command
 * removed: leading VAR=value assignments, `env`, `command`, `builtin`,
 * `exec`, `time`, `nice`, `nohup`, `timeout` and its duration, a directory
 * on the program name, and git's global options. Rules
 * then match `git -C . push -f` and `FOO=1 command git push -f` as
 * `git push -f`.
 */
export function normalizedWords(segment: string): string[] {
  const words = shellWords(segment);
  let i = 0;
  while (i < words.length) {
    const name = programName(words[i]);
    if (ASSIGNMENT.test(words[i])) i++;
    else if (OPTION_WRAPPERS.has(name)) {
      i++;
      const valueOptions = OPTION_WRAPPERS.get(name) ?? new Set<string>();
      while (i < words.length && words[i].startsWith('-')) {
        if (words[i] === '--') {
          i++;
          break;
        }
        i += valueOptions.has(words[i]) ? 2 : 1;
      }
      if (name === 'timeout') i++;
    } else break;
  }
  const rest = words.slice(i);
  if (rest.length > 0) rest[0] = programName(rest[0]);
  if (rest[0] !== 'git') return rest;
  let j = 1;
  while (j < rest.length && rest[j].startsWith('-')) {
    if (GIT_VALUE_OPTIONS.has(rest[j])) j += 2;
    else j++;
  }
  return ['git', ...rest.slice(j)];
}

/** A segment as one space-separated line, for matching against command globs. */
export function normalizeSegment(segment: string): string {
  return normalizedWords(segment).join(' ');
}

/* Push options whose value is the next word. */
const PUSH_VALUE_OPTIONS = new Set(['-o', '--push-option', '--repo', '--receive-pack', '--exec']);

/* The refspecs follow the remote, unless `--repo` names the remote as a flag. */
function pushArgs(words: string[]): { flags: string[]; refspecs: string[] } | undefined {
  if (words[0] !== 'git' || words[1] !== 'push') return undefined;
  const flags: string[] = [];
  const positionals: string[] = [];
  for (let i = 2; i < words.length; i++) {
    const word = words[i];
    if (word === '--') {
      positionals.push(...words.slice(i + 1));
      break;
    }
    if (word.startsWith('-') && word.length > 1) {
      flags.push(word);
      if (PUSH_VALUE_OPTIONS.has(word)) i++;
    } else positionals.push(word);
  }
  const namesRepo = flags.some((f) => f === '--repo' || f.startsWith('--repo='));
  return { flags, refspecs: namesRepo ? positionals : positionals.slice(1) };
}

/** `git push` that overwrites remote history: a force flag, a `+` refspec, or `--mirror`. */
export function isForcePush(words: string[]): boolean {
  const args = pushArgs(words);
  if (args === undefined) return false;
  const forceFlag = args.flags.some(
    (f) =>
      f === '--force' ||
      f === '--mirror' ||
      f.startsWith('--force-with-lease') ||
      f === '--force-if-includes' ||
      /^-[A-Za-z0-9]*f[A-Za-z0-9]*$/.test(f),
  );
  return forceFlag || args.refspecs.some((p) => p.startsWith('+'));
}

/** `git push` naming `branch` as a destination: `main`, `HEAD:main`, `:main`, `x:refs/heads/main`. */
export function pushesToBranch(words: string[], branch: string): boolean {
  const args = pushArgs(words);
  if (args === undefined) return false;
  return args.refspecs.some((spec) => {
    const dst = spec.replace(/^\+/, '').split(':').pop() ?? '';
    return dst === branch || dst === `refs/heads/${branch}`;
  });
}

/** `rm` with both a recursive and a force flag, in any order or grouping. */
export function isRecursiveForceRm(words: string[]): boolean {
  if (words[0] !== 'rm') return false;
  let recursive = false;
  let force = false;
  for (const word of words.slice(1)) {
    if (word === '--') break;
    if (word === '--recursive') recursive = true;
    else if (word === '--force') force = true;
    else if (/^-[A-Za-z]+$/.test(word)) {
      if (/[rR]/.test(word)) recursive = true;
      if (word.includes('f')) force = true;
    }
  }
  return recursive && force;
}

/**
 * Glob rules that a flag reorder or a refspec form slips past, paired with the
 * check that catches every form. Each check applies only while its rule is in
 * the deny list, so settings.json stays the one source of what is denied.
 */
function structuralCheck(pattern: string): ((words: string[]) => boolean) | undefined {
  if (pattern === 'rm -rf *' || pattern === 'rm -fr *') return isRecursiveForceRm;
  if (pattern === 'git push --force *' || pattern === 'git push -f *' || pattern === 'git push --force-with-lease *') return isForcePush;
  const branch = /^git push (?:\* (\S+)|origin (\S+) \*)$/.exec(pattern);
  if (branch !== null) {
    const name = branch[1] ?? branch[2];
    return (words) => pushesToBranch(words, name);
  }
  return undefined;
}

/** The first Bash rule a command breaks, matching each segment raw, normalized, and structurally. */
export function matchBashRule(command: string, rules: DenyRule[]): DenyRule | undefined {
  const segments = commandSegments(command);
  const normalized = segments.slice(1).map((s) => normalizedWords(s));
  for (const rule of rules.filter((r) => r.family === 'bash')) {
    if (segments.some((s) => commandGlobMatches(rule.pattern, s))) return rule;
    if (normalized.some((words) => commandGlobMatches(rule.pattern, words.join(' ')))) return rule;
    const check = structuralCheck(rule.pattern);
    if (check !== undefined && normalized.some(check)) return rule;
  }
  return undefined;
}

/* Existence and listing checks name a file without reading it. */
const NON_READING = [/^test\s/, /^\[\s/, /^ls(\s|$)/, /^stat\s/, /^git check-ignore\s/];

export interface EvaluateOptions {
  home?: string;
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
    const bashHit = matchBashRule(command, rules);
    if (bashHit !== undefined) return { rule: bashHit.source, subject: command };
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
  /* Codex has no native deny rules, so a gate that cannot decide blocks there.
     Elsewhere the host's own rules still apply, so it passes. */
  const failClosed = process.env.AGENT_HOOK_HOST === 'codex';
  const cannotDecide = (reason: string): void => {
    if (!failClosed) return;
    process.stderr.write(`[deny-gate] Cannot check the deny list (${reason}), and Codex has no other deny enforcement. Fix the gate before continuing.\n`);
    process.exitCode = 2;
  };
  const config = loadGateConfig(source);
  if (config.status !== 'ok') return cannotDecide(config.reason);
  let payload: HookPayload;
  try {
    payload = JSON.parse(readFileSync(0, 'utf8')) as HookPayload;
  } catch {
    return cannotDecide('the hook payload is not JSON');
  }
  const verdict = evaluate(payload, config.rules);
  if (verdict === undefined) return;
  process.stderr.write(`[deny-gate] Blocked by the deny rule ${verdict.rule}: ${verdict.subject}\n`);
  process.stderr.write('The deny list in settings.json forbids this. Find another way or ask the user.\n');
  process.exitCode = 2;
}

/* Hosts reach this file through symlinked hook dirs; compare real paths. */
if (process.argv[1] !== undefined && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) main();
