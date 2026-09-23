/**
 * Tests for hooks/lib/deny-gate.ts: glob and path matching, command splitting,
 * the evaluation per tool, and the hook wrapper's exit codes.
 */

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { after, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  candidatePaths,
  commandGlobMatches,
  commandSegments,
  evaluate,
  pathGlobToRegex,
  stripHeredocs,
} from '../hooks/lib/deny-gate.ts';
import type { DenyRule } from '../pi/extensions/permission-gate.ts';

const HOME = '/home/u';
const CWD = '/work/app';

const rules: DenyRule[] = [
  { family: 'path-read', pattern: '**/.env', source: 'Read(**/.env)' },
  { family: 'path-read', pattern: '~/.ssh/**', source: 'Read(~/.ssh/**)' },
  { family: 'path-read', pattern: '**/*.pem', source: 'Read(**/*.pem)' },
  { family: 'path-write', pattern: '**/.env.local', source: 'Edit(**/.env.local)' },
  { family: 'bash', pattern: 'sudo *', source: 'Bash(sudo *)' },
  { family: 'bash', pattern: '*DROP TABLE*', source: 'Bash(*DROP TABLE*)' },
  { family: 'mcp', pattern: 'mcp__jira__*', source: 'mcp__jira__*' },
];

const bash = (command: string) => ({ tool_name: 'Bash', tool_input: { command }, cwd: CWD });

describe('commandGlobMatches', () => {
  it('treats * as any text and nothing else as special', () => {
    assert.equal(commandGlobMatches('sudo *', 'sudo rm x'), true);
    assert.equal(commandGlobMatches('a.b *', 'aXb c'), false);
  });

  it('lets a trailing space-star match the bare command', () => {
    assert.equal(commandGlobMatches('git push *', 'git push'), true);
  });
});

describe('commandSegments', () => {
  it('splits top-level operators but not quoted text', () => {
    assert.deepEqual(commandSegments("cd x && ssh h 'a; sudo b' | tail"), [
      "cd x && ssh h 'a; sudo b' | tail",
      'cd x',
      "ssh h 'a; sudo b'",
      'tail',
    ]);
  });

  it('keeps heredoc bodies out of the segments', () => {
    assert.deepEqual(commandSegments('cat > f <<EOF\nsudo x\nEOF').slice(1), ['cat > f <<EOF']);
  });
});

describe('pathGlobToRegex', () => {
  it('anchors ~/ at home and ** across directories', () => {
    assert.equal(pathGlobToRegex('~/.ssh/**', HOME).test('/home/u/.ssh/id_rsa'), true);
    assert.equal(pathGlobToRegex('~/.ssh/**', HOME).test('/other/.ssh/id_rsa'), false);
  });

  it('matches an unanchored name at any depth, * within one segment', () => {
    assert.equal(pathGlobToRegex('**/.env', HOME).test('/work/app/.env'), true);
    assert.equal(pathGlobToRegex('**/.env', HOME).test('/work/app/.env.example'), false);
    assert.equal(pathGlobToRegex('**/*.pem', HOME).test('/a/b/c.pem'), true);
  });
});

describe('stripHeredocs', () => {
  it('drops the body through the terminator', () => {
    assert.equal(stripHeredocs("a <<'X'\nsecret\nX\nb"), "a <<'X'\nb");
  });
});

describe('candidatePaths', () => {
  it('resolves words against cwd and home, skipping flags, assignments, and prose', () => {
    assert.deepEqual(candidatePaths('grep -n x ~/.npmrc "two words" KEY=/a/.env src/.env', CWD, HOME), [
      '/work/app/grep',
      '/work/app/x',
      '/home/u/.npmrc',
      '/work/app/src/.env',
    ]);
  });
});

describe('evaluate', () => {
  it('blocks a shell command that names a denied path', () => {
    assert.equal(evaluate(bash('cat .env'), rules, { home: HOME })?.rule, 'Read(**/.env)');
    assert.equal(evaluate(bash('sed -n 1p ~/.ssh/config'), rules, { home: HOME })?.rule, 'Read(~/.ssh/**)');
  });

  it('lets existence checks and quoted prose through', () => {
    assert.equal(evaluate(bash('test -f .env && ls .env'), rules, { home: HOME }), undefined);
    assert.equal(evaluate(bash('git commit -m "ignore .env"'), rules, { home: HOME }), undefined);
  });

  it('applies Bash rules only when asked', () => {
    assert.equal(evaluate(bash('cd x && sudo ls'), rules, { home: HOME }), undefined);
    assert.equal(evaluate(bash('cd x && sudo ls'), rules, { home: HOME, bashRules: true })?.rule, 'Bash(sudo *)');
    assert.equal(evaluate(bash("ssh h 'sudo ls'"), rules, { home: HOME, bashRules: true }), undefined);
  });

  it('checks edits and MCP tools', () => {
    const edit = { tool_name: 'Edit', tool_input: { file_path: 'app/.env.local' }, cwd: '/w' };
    assert.equal(evaluate(edit, rules, { home: HOME })?.subject, '/w/app/.env.local');
    assert.equal(evaluate({ tool_name: 'mcp__jira__getIssue' }, rules)?.rule, 'mcp__jira__*');
    assert.equal(evaluate({ tool_name: 'mcp__slack__post' }, rules), undefined);
  });
});

describe('hook wrapper', () => {
  const dir = mkdtempSync(join(tmpdir(), 'deny-gate-'));
  after(() => rmSync(dir, { recursive: true, force: true }));
  const source = join(dir, 'settings.json');
  writeFileSync(source, JSON.stringify({ permissions: { deny: ['Read(**/.env)', 'Bash(sudo *)'] } }));
  const wrapper = join(dirname(fileURLToPath(import.meta.url)), '..', 'hooks', 'deny-gate.sh');
  const run = (payload: object, host?: string) =>
    spawnSync('bash', [wrapper], {
      input: JSON.stringify(payload),
      env: { ...process.env, DENY_RULES_SOURCE: source, AGENT_HOOK_HOST: host ?? '' },
      encoding: 'utf8',
    });

  it('exits 2 with the rule on stderr', () => {
    const result = run({ ...bash('cat .env'), cwd: dir });
    assert.equal(result.status, 2);
    assert.match(result.stderr, /Read\(\*\*\/\.env\)/);
  });

  it('enforces Bash rules on Codex only', () => {
    assert.equal(run(bash('sudo ls')).status, 0);
    assert.equal(run(bash('sudo ls'), 'codex').status, 2);
    assert.equal(run(bash('sudo ls'), 'pi').status, 0);
  });

  it('passes a malformed payload', () => {
    const result = spawnSync('bash', [wrapper], { input: 'not json', env: { ...process.env, DENY_RULES_SOURCE: source }, encoding: 'utf8' });
    assert.equal(result.status, 0);
  });
});
