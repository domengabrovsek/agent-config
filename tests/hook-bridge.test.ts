/**
 * Tests for hook-bridge: pure payload translation and exit-code mapping, plus
 * runDispatcher against fake dispatcher scripts in a temp dir. The real
 * hooks/lib/dispatch.sh is never invoked, so these tests do not depend on the
 * hooks registered in settings.json.
 */

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { after, before, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';

import registerBridge, {
  appendText,
  buildHookPayload,
  buildSessionEndPayload,
  buildSessionStartPayload,
  claimBridge,
  interpretDispatch,
  parseActiveAgent,
  releaseBridge,
  resolvePiPath,
  runDispatcher,
  toClaudeToolName,
  type HookPayload,
} from '../pi/extensions/hook-bridge.ts';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..');

describe('toClaudeToolName', () => {
  it('maps bash, edit, and write', () => {
    assert.equal(toClaudeToolName('bash'), 'Bash');
    assert.equal(toClaudeToolName('edit'), 'Edit');
    assert.equal(toClaudeToolName('write'), 'Write');
  });

  it('skips tools the hooks never see', () => {
    for (const name of ['read', 'grep', 'find', 'ls', 'mcp', 'toString', '__proto__']) {
      assert.equal(toClaudeToolName(name), undefined, name);
    }
  });
});

describe('resolvePiPath', () => {
  it('resolves relative paths against cwd', () => {
    assert.equal(resolvePiPath('src/a.ts', '/repo'), '/repo/src/a.ts');
    assert.equal(resolvePiPath('../b.ts', '/repo/src'), '/repo/b.ts');
  });

  it('keeps absolute paths and strips the @ mention prefix', () => {
    assert.equal(resolvePiPath('/abs/c.ts', '/repo'), '/abs/c.ts');
    assert.equal(resolvePiPath('@src/a.ts', '/repo'), '/repo/src/a.ts');
  });

  it('expands ~', () => {
    assert.equal(resolvePiPath('~/x.md', '/repo', '/home/u'), '/home/u/x.md');
    assert.equal(resolvePiPath('~', '/repo', '/home/u'), '/home/u');
  });
});

describe('buildHookPayload', () => {
  it('builds a Bash payload from the command', () => {
    assert.deepEqual(
      buildHookPayload({ event: 'PreToolUse', piToolName: 'bash', input: { command: 'git push' }, cwd: '/repo', sessionId: 's1' }),
      { hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: { command: 'git push' }, cwd: '/repo', session_id: 's1' },
    );
  });

  it('builds Edit and Write payloads with an absolute file_path', () => {
    const edit = buildHookPayload({ event: 'PostToolUse', piToolName: 'edit', input: { path: 'tests/a.test.ts', edits: [] }, cwd: '/repo' });
    assert.deepEqual(edit?.tool_input, { file_path: '/repo/tests/a.test.ts' });
    assert.equal(edit?.tool_name, 'Edit');
    const write = buildHookPayload({ event: 'PreToolUse', piToolName: 'write', input: { path: '/abs/b.ts', content: '' }, cwd: '/repo' });
    assert.equal(write?.tool_name, 'Write');
    assert.deepEqual(write?.tool_input, { file_path: '/abs/b.ts' });
  });

  it('includes agent_type only for subagents', () => {
    const child = buildHookPayload({ event: 'PreToolUse', piToolName: 'edit', input: { path: 'a' }, cwd: '/r', agentType: 'QA Expert' });
    assert.equal(child?.agent_type, 'QA Expert');
    const main = buildHookPayload({ event: 'PreToolUse', piToolName: 'edit', input: { path: 'a' }, cwd: '/r' });
    assert.equal(main !== undefined && 'agent_type' in main, false);
  });

  it('returns undefined for unmapped tools and malformed input', () => {
    assert.equal(buildHookPayload({ event: 'PreToolUse', piToolName: 'read', input: { path: 'a' }, cwd: '/r' }), undefined);
    assert.equal(buildHookPayload({ event: 'PreToolUse', piToolName: 'bash', input: {}, cwd: '/r' }), undefined);
    assert.equal(buildHookPayload({ event: 'PreToolUse', piToolName: 'edit', input: { path: '' }, cwd: '/r' }), undefined);
  });
});

describe('parseActiveAgent', () => {
  it('reads the XML-attribute form from child-launch', () => {
    assert.equal(parseActiveAgent('<active_agent name="QA Expert"/>\n\nYou are...'), 'QA Expert');
    assert.equal(parseActiveAgent('x <active_agent name="R&amp;D &quot;Lead&quot;"/> y'), 'R&D "Lead"');
  });

  it('reads the JSON-string form from the herdr bridge', () => {
    assert.equal(parseActiveAgent(`base\n\n<active_agent name=${JSON.stringify('PR Reviewer')}/>\n\nbody`), 'PR Reviewer');
    assert.equal(parseActiveAgent(`<active_agent name=${JSON.stringify('a "b"')}/>`), 'a "b"');
  });

  it('returns undefined for the main session', () => {
    assert.equal(parseActiveAgent('You are pi, a coding agent.'), undefined);
    assert.equal(parseActiveAgent('<active_agent name=""/>'), undefined);
  });
});

describe('interpretDispatch', () => {
  const run = (code: number | null, stdout = '', stderr = '', timedOut = false) => ({ code, stdout, stderr, timedOut });

  it('blocks on exit 2 with the stderr reason', () => {
    assert.deepEqual(interpretDispatch('PreToolUse', run(2, '', 'Blocked: tests are locked\n')), {
      kind: 'block',
      reason: 'Blocked: tests are locked',
    });
  });

  it('blocks on exit 2 with a default reason when stderr is empty', () => {
    const outcome = interpretDispatch('PreToolUse', run(2));
    assert.equal(outcome.kind, 'block');
  });

  it('passes exit 0 and extracts additionalContext', () => {
    const stdout = JSON.stringify({ hookSpecificOutput: { hookEventName: 'PreToolUse', additionalContext: '[pr-state] open' } });
    assert.deepEqual(interpretDispatch('PreToolUse', run(0, stdout)), { kind: 'pass', context: '[pr-state] open' });
    assert.deepEqual(interpretDispatch('PreToolUse', run(0, 'not json')), { kind: 'pass' });
    assert.deepEqual(interpretDispatch('PreToolUse', run(0)), { kind: 'pass' });
  });

  it('treats other exits and timeouts as non-blocking with a notice', () => {
    const failed = interpretDispatch('PostToolUse', run(1, '', 'boom'));
    assert.equal(failed.kind, 'pass');
    assert.match(failed.kind === 'pass' ? (failed.notice ?? '') : '', /exit 1.*boom/);
    const timedOut = interpretDispatch('PreToolUse', run(null, '', '', true));
    assert.equal(timedOut.kind, 'pass');
    assert.match(timedOut.kind === 'pass' ? (timedOut.notice ?? '') : '', /timed out/);
  });
});

describe('appendText', () => {
  it('appends a text block without mutating the original', () => {
    const content = [{ type: 'text' as const, text: 'ok' }];
    assert.deepEqual(appendText(content, 'note'), [{ type: 'text', text: 'ok' }, { type: 'text', text: 'note' }]);
    assert.equal(content.length, 1);
  });
});

describe('runDispatcher', () => {
  const dir = mkdtempSync(join(tmpdir(), 'hook-bridge-'));
  after(() => rmSync(dir, { recursive: true, force: true }));

  const fake = (name: string, body: string): string => {
    const path = join(dir, name);
    writeFileSync(path, `#!/usr/bin/env bash\n${body}\n`);
    chmodSync(path, 0o755);
    return path;
  };
  const payload: HookPayload = { hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: { command: 'ls' }, cwd: dir };

  it('passes the event as argv and the payload on stdin', async () => {
    const capture = join(dir, 'stdin.json');
    const script = fake('echo.sh', `echo "$1" > "${capture}.event"; cat > "${capture}"`);
    const result = await runDispatcher(script, 'PreToolUse', payload, { cwd: dir });
    assert.equal(result.code, 0);
    assert.equal(readFileSync(`${capture}.event`, 'utf8').trim(), 'PreToolUse');
    assert.deepEqual(JSON.parse(readFileSync(capture, 'utf8')), payload);
  });

  it('reports exit 2 with stderr', async () => {
    const script = fake('block.sh', 'cat >/dev/null; echo "Blocked: no" >&2; exit 2');
    const result = await runDispatcher(script, 'PreToolUse', payload, { cwd: dir });
    assert.deepEqual(interpretDispatch('PreToolUse', result), { kind: 'block', reason: 'Blocked: no' });
  });

  it('tells the dispatcher it runs on Pi', async () => {
    const script = fake('host.sh', 'cat >/dev/null; echo "$AGENT_HOOK_HOST" >&2; exit 2');
    const result = await runDispatcher(script, 'PreToolUse', payload, { cwd: dir });
    assert.deepEqual(interpretDispatch('PreToolUse', result), { kind: 'block', reason: 'pi' });
  });

  it('returns stdout context on exit 0', async () => {
    const script = fake('ctx.sh', `cat >/dev/null; echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"hi"}}'`);
    const result = await runDispatcher(script, 'PreToolUse', payload, { cwd: dir });
    assert.deepEqual(interpretDispatch('PreToolUse', result), { kind: 'pass', context: 'hi' });
  });

  it('kills a slow dispatcher at the timeout and fails open', async () => {
    const script = fake('slow.sh', 'sleep 30');
    const started = Date.now();
    const result = await runDispatcher(script, 'PreToolUse', payload, { cwd: dir, timeoutMs: 200 });
    assert.equal(result.timedOut, true);
    assert.ok(Date.now() - started < 5000);
    assert.equal(interpretDispatch('PreToolUse', result).kind, 'pass');
  });

  it('survives a dispatcher that exits without reading stdin', async () => {
    const script = fake('noread.sh', 'exit 0');
    const result = await runDispatcher(script, 'PreToolUse', payload, { cwd: dir });
    assert.equal(result.code, 0);
  });
});

describe('claimBridge', () => {
  it('lets only the first load register', () => {
    const scope: Record<symbol, unknown> = {};
    assert.equal(claimBridge(scope), true);
    assert.equal(claimBridge(scope), false);
  });
});

describe('releaseBridge', () => {
  it('lets the next session runtime register again', () => {
    const scope: Record<symbol, unknown> = {};
    assert.equal(claimBridge(scope), true);
    releaseBridge(scope);
    assert.equal(claimBridge(scope), true);
  });
});

describe('buildSessionStartPayload', () => {
  it('maps pi start reasons onto Claude sources', () => {
    const sources = (['startup', 'resume', 'fork', 'new'] as const).map(
      (reason) => buildSessionStartPayload({ reason, cwd: '/r' })?.source,
    );
    assert.deepEqual(sources, ['startup', 'resume', 'resume', 'clear']);
    assert.deepEqual(buildSessionStartPayload({ reason: 'startup', cwd: '/r', sessionId: 's1' }), {
      hook_event_name: 'SessionStart',
      source: 'startup',
      cwd: '/r',
      session_id: 's1',
    });
  });

  it('skips a reload and a subagent child', () => {
    assert.equal(buildSessionStartPayload({ reason: 'reload', cwd: '/r' }), undefined);
    assert.equal(buildSessionStartPayload({ reason: 'startup', cwd: '/r', agentType: 'QA Expert' }), undefined);
  });
});

describe('buildSessionEndPayload', () => {
  it('maps pi shutdown reasons onto Claude reasons', () => {
    const reasons = (['quit', 'new', 'resume', 'fork'] as const).map(
      (reason) => buildSessionEndPayload({ reason, cwd: '/r' })?.reason,
    );
    assert.deepEqual(reasons, ['prompt_input_exit', 'clear', 'resume', 'other']);
  });

  it('skips a reload and a subagent child', () => {
    assert.equal(buildSessionEndPayload({ reason: 'reload', cwd: '/r' }), undefined);
    assert.equal(buildSessionEndPayload({ reason: 'quit', cwd: '/r', agentType: 'QA Expert' }), undefined);
  });
});

type Handler = (event: object, ctx: object) => unknown;

/* Registers the bridge against a fake pi that records its handlers. */
function registerFake(): Map<string, Handler> {
  const handlers = new Map<string, Handler>();
  const pi: Pick<ExtensionAPI, 'on'> = {
    on(name: string, handler: (event: never, ctx: never) => unknown) {
      handlers.set(name, handler as Handler);
    },
  };
  registerBridge(pi as ExtensionAPI);
  return handlers;
}

/* A fresh session runtime. The bridge runs the real hooks/lib/dispatch.sh. */
function loadBridge(): Map<string, Handler> {
  releaseBridge();
  return registerFake();
}

describe('session events through the dispatcher', () => {
  const dir = mkdtempSync(join(tmpdir(), 'hook-bridge-session-'));
  const log = join(dir, 'log');
  const registry = join(dir, 'settings.json');
  const ctx = {
    cwd: dir,
    hasUI: false,
    getSystemPrompt: () => '',
    sessionManager: { getSessionId: () => 's1' },
  };
  const record = `cat >> '${log}'; echo >> '${log}'`;
  const logged = (): Record<string, string>[] =>
    existsSync(log)
      ? readFileSync(log, 'utf8').split('\n').filter((line) => line.trim()).map((line) => JSON.parse(line))
      : [];
  const savedRegistry = process.env.HOOK_REGISTRY;

  before(() => {
    writeFileSync(
      registry,
      JSON.stringify({
        hooks: {
          SessionStart: [{ matcher: 'startup', hooks: [{ type: 'command', command: record }] }],
          SessionEnd: [{ hooks: [{ type: 'command', command: record }] }],
        },
      }),
    );
    process.env.HOOK_REGISTRY = registry;
  });
  after(() => {
    if (savedRegistry === undefined) delete process.env.HOOK_REGISTRY;
    else process.env.HOOK_REGISTRY = savedRegistry;
    releaseBridge();
    rmSync(dir, { recursive: true, force: true });
  });

  it('runs SessionStart hooks matched on the startup source', async () => {
    rmSync(log, { force: true });
    const handlers = loadBridge();
    await handlers.get('session_start')?.({ type: 'session_start', reason: 'startup' }, ctx);
    assert.deepEqual(logged(), [{ hook_event_name: 'SessionStart', source: 'startup', cwd: dir, session_id: 's1' }]);
  });

  it('skips a start matcher for another source', async () => {
    rmSync(log, { force: true });
    const handlers = loadBridge();
    await handlers.get('session_start')?.({ type: 'session_start', reason: 'resume' }, ctx);
    assert.deepEqual(logged(), []);
  });

  it('runs SessionEnd hooks on quit', async () => {
    rmSync(log, { force: true });
    const handlers = loadBridge();
    await handlers.get('session_shutdown')?.({ type: 'session_shutdown', reason: 'quit' }, ctx);
    assert.deepEqual(logged(), [{ hook_event_name: 'SessionEnd', reason: 'prompt_input_exit', cwd: dir, session_id: 's1' }]);
  });

  it('finishes a slow SessionEnd hook before the handler returns', async () => {
    const slowRegistry = join(dir, 'slow.json');
    const marker = join(dir, 'pruned');
    writeFileSync(
      slowRegistry,
      JSON.stringify({ hooks: { SessionEnd: [{ hooks: [{ type: 'command', command: `cat >/dev/null; sleep 0.5; touch '${marker}'` }] }] } }),
    );
    process.env.HOOK_REGISTRY = slowRegistry;
    try {
      const handlers = loadBridge();
      await handlers.get('session_shutdown')?.({ type: 'session_shutdown', reason: 'quit' }, ctx);
      assert.equal(existsSync(marker), true);
    } finally {
      process.env.HOOK_REGISTRY = registry;
    }
  });

  it('fires no SessionEnd on a reload, and the reloaded runtime registers again', async () => {
    rmSync(log, { force: true });
    const handlers = loadBridge();
    await handlers.get('session_shutdown')?.({ type: 'session_shutdown', reason: 'reload' }, ctx);
    assert.deepEqual(logged(), []);
    const next = registerFake();
    assert.ok(next.has('session_start') && next.has('tool_call'));
  });
});

describe('Claude-only session hooks in settings.json', () => {
  const home = mkdtempSync(join(tmpdir(), 'hook-bridge-home-'));
  after(() => rmSync(home, { recursive: true, force: true }));
  const registry: { hooks: { SessionStart: { hooks: { command: string }[] }[] } } = JSON.parse(
    readFileSync(join(REPO, 'settings.json'), 'utf8'),
  );
  const commands = registry.hooks.SessionStart.flatMap((group) => group.hooks.map((hook) => hook.command));

  for (const name of ['herdr-agent-state.sh', 'symlink-check.sh']) {
    it(`runs ${name} on Claude only`, () => {
      const command = commands.find((text) => text.includes(`/${name}`));
      assert.ok(command, `${name} is registered`);
      const hooks = join(home, '.claude/hooks');
      const marker = join(home, `${name}.ran`);
      mkdirSync(hooks, { recursive: true });
      writeFileSync(join(hooks, name), `#!/bin/bash\ntouch '${marker}'\n`);
      chmodSync(join(hooks, name), 0o755);
      const ran = (host: string | undefined): boolean => {
        rmSync(marker, { force: true });
        const env: NodeJS.ProcessEnv = { PATH: process.env.PATH, HOME: home };
        if (host !== undefined) env.AGENT_HOOK_HOST = host;
        spawnSync('bash', ['-c', command], { env, input: '{}' });
        return existsSync(marker);
      };
      assert.deepEqual([ran(undefined), ran('codex'), ran('pi')], [true, false, false]);
    });
  }
});
