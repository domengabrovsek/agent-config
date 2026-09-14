/**
 * Tests for permission-gate's derived-policy generator: a pure unit layer on
 * translation edges, plus two drift alarms against the real deny list -
 * every rule in the real root settings.json must classify (no silent skips),
 * and the committed derived config must equal a fresh derivation byte for
 * byte, so deny-list edits fail here instead of shipping a stale config.
 */

// Lives under tests/ (not pi/extensions/) because pi auto-discovers every
// *.ts directly inside extensions/ and would load this file as an extension.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it } from 'node:test';

import {
  buildPolicyDocument,
  classifyRule,
  derivePermissionPolicy,
  loadGateConfig,
  resolvePermissionSource,
  serializePolicyDocument,
  translateMcpRule,
  translatePathPattern,
  type DenyRule,
} from '../pi/extensions/permission-gate.ts';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const realSettings = join(repoRoot, 'settings.json');
const committedConfig = join(repoRoot, 'pi/extensions/pi-permission-system/config.json');

describe('classifyRule', () => {
  it('binds Read rules to path-read', () => {
    assert.deepEqual(classifyRule('Read(**/.env)'), { family: 'path-read', pattern: '**/.env' });
  });

  it('binds Edit and Write rules to the write family', () => {
    assert.equal(classifyRule('Edit(~/.ssh/**)')?.family, 'path-write');
    assert.equal(classifyRule('Write(**/credentials.json)')?.family, 'path-write');
  });

  it('binds Bash rules to bash', () => {
    assert.deepEqual(classifyRule('Bash(sudo *)'), { family: 'bash', pattern: 'sudo *' });
  });

  it('classifies MCP rules with single-underscore server names', () => {
    assert.deepEqual(classifyRule('mcp__claude_ai_Atlassian__*'), {
      family: 'mcp',
      pattern: 'mcp__claude_ai_Atlassian__*',
    });
  });

  it('leaves unknown rules unclassified', () => {
    assert.equal(classifyRule('WebFetch(*)'), undefined);
    assert.equal(classifyRule('mcp__broken__'), undefined);
    assert.equal(classifyRule('mcp__a'), undefined);
  });
});

describe('translatePathPattern', () => {
  it('collapses ** to their cross-segment *', () => {
    assert.equal(translatePathPattern('~/.ssh/**'), '~/.ssh/*');
    assert.equal(translatePathPattern('**/.env'), '*/.env');
    assert.equal(translatePathPattern('**/*.pem'), '*/*.pem');
  });

  it('keeps single stars and literal segments verbatim', () => {
    assert.equal(translatePathPattern('~/.vault-token'), '~/.vault-token');
    assert.equal(translatePathPattern('~/.config/Code/User/globalStorage/**'), '~/.config/Code/User/globalStorage/*');
  });
});

describe('translateMcpRule', () => {
  it('maps a wildcard tool to a server prefix pattern', () => {
    assert.equal(translateMcpRule('mcp__claude_ai_Atlassian__*'), 'claude_ai_Atlassian*');
  });

  it('maps a named tool to the server:tool form', () => {
    assert.equal(translateMcpRule('mcp__exa__web_search'), 'exa:web_search');
  });

  it('rejects malformed rules', () => {
    assert.equal(translateMcpRule('mcp__a'), undefined);
    assert.equal(translateMcpRule('mcp__a__'), undefined);
  });
});

describe('derivePermissionPolicy', () => {
  const rule = (family: DenyRule['family'], pattern: string, source = `${family}:${pattern}`): DenyRule => ({
    family,
    pattern,
    source,
  });

  it('keeps read and write directions separate', () => {
    const policy = derivePermissionPolicy({
      status: 'ok',
      rules: [rule('path-read', '~/.ssh/**'), rule('path-write', '**/package-lock.json')],
      skipped: [],
      allowCount: 0,
    });
    assert.deepEqual(policy.pathRead, { '~/.ssh/*': 'deny' });
    assert.deepEqual(policy.pathWrite, { '*/package-lock.json': 'deny' });
  });

  it('deduplicates mirrored patterns and sorts deterministically', () => {
    const policy = derivePermissionPolicy({
      status: 'ok',
      rules: [rule('path-read', '**/.env'), rule('path-read', '~/.vault-token'), rule('path-read', '**/.env')],
      skipped: [],
      allowCount: 0,
    });
    assert.deepEqual(Object.keys(policy.pathRead), ['*/.env', '~/.vault-token']);
  });

  it('passes bash patterns through and translates MCP rules', () => {
    const policy = derivePermissionPolicy({
      status: 'ok',
      rules: [rule('bash', 'rm -rf *'), rule('bash', 'rm -rf *'), rule('mcp', 'mcp__exa__*')],
      skipped: [],
      allowCount: 0,
    });
    assert.deepEqual(policy.bash, { 'rm -rf *': 'deny' });
    assert.deepEqual(policy.mcp, { 'exa*': 'deny' });
  });

  it('always sets the universal fallback to allow, never ask', () => {
    const policy = derivePermissionPolicy({ status: 'ok', rules: [], skipped: [], allowCount: 0 });
    assert.equal(policy.universal, 'allow');
  });
});

describe('buildPolicyDocument', () => {
  it('omits empty surfaces and emits only deny states', () => {
    const doc = buildPolicyDocument({
      universal: 'allow',
      pathRead: { '*/.env': 'deny' },
      pathWrite: {},
      bash: { 'sudo *': 'deny' },
      mcp: {},
    });
    assert.deepEqual(Object.keys(doc.permission), ['*', 'path_read', 'bash']);
    assert.equal(doc.permission['*'], 'allow');
  });

  it('serializes deterministically with a trailing newline', () => {
    const doc = buildPolicyDocument({
      universal: 'allow',
      pathRead: { '*/.env': 'deny' },
      pathWrite: {},
      bash: {},
      mcp: {},
    });
    assert.equal(serializePolicyDocument(doc), serializePolicyDocument(doc));
    assert.ok(serializePolicyDocument(doc).endsWith('}\n'));
  });
});

describe('real deny list (drift alarms)', () => {
  const selection = resolvePermissionSource([realSettings]);

  it('resolves the tracked settings.json as the permission source', () => {
    assert.equal(selection.status, 'ok', 'tracked root settings.json must exist and carry a deny list');
  });

  it('classifies every deny rule - no silent skips', () => {
    assert.ok(selection.status === 'ok');
    assert.deepEqual(
      selection.config.skipped,
      [],
      `every deny rule must translate; untranslatable: ${selection.config.skipped.join(', ')}`,
    );
  });

  it('leaves package-manager lockfiles writable', () => {
    assert.ok(selection.status === 'ok');
    const policy = derivePermissionPolicy(selection.config);

    assert.equal(policy.pathWrite['*/package-lock.json'], undefined);
    assert.equal(policy.pathWrite['*/pnpm-lock.yaml'], undefined);
    assert.equal(policy.pathWrite['*/yarn.lock'], undefined);
  });

  it('matches the committed derived config byte for byte', () => {
    assert.ok(selection.status === 'ok');
    const document = buildPolicyDocument(derivePermissionPolicy(selection.config));
    const expected = serializePolicyDocument(document);
    const actual = readFileSync(join(repoRoot, 'pi/extensions/pi-permission-system/config.json'), 'utf8');
    assert.equal(actual, expected, 'derived policy drifted from the tracked config; regenerate it');
  });

  it('keeps loadGateConfig resilient on bad sources', () => {
    assert.equal(loadGateConfig('/nonexistent/settings.json').status, 'missing');
  });
});