/**
 * Tests for worktree-cleanup: the pure decision predicate deciding which
 * shutdown reasons prune and how the disable knob and its legacy spelling
 * turn it off. Script resolution and invocation stay glue.
 */

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  cleanupDisabledByEnv,
  shouldCleanup,
  type ShutdownReason,
} from '../pi/extensions/worktree-cleanup.ts';

const ENV_EMPTY: Record<string, string | undefined> = {};

describe('shouldCleanup', () => {
  const realEnds: ShutdownReason[] = ['quit', 'new', 'resume', 'fork'];

  it('runs on every real session end', () => {
    for (const reason of realEnds) {
      assert.equal(shouldCleanup(reason, ENV_EMPTY), true, reason);
    }
  });

  it('never runs on reload', () => {
    assert.equal(shouldCleanup('reload', ENV_EMPTY), false);
  });

  it('is disabled by HARNESS_DISABLE_WORKTREE_CLEANUP=1', () => {
    assert.equal(shouldCleanup('quit', { HARNESS_DISABLE_WORKTREE_CLEANUP: '1' }), false);
    assert.equal(shouldCleanup('resume', { CLAUDE_DISABLE_WORKTREE_CLEANUP: '0' }), true);
  });

  it('falls back to the legacy CLAUDE_ spelling', () => {
    const env: Record<string, string | undefined> = { CLAUDE_DISABLE_WORKTREE_CLEANUP: '1' };
    assert.equal(shouldCleanup('quit', env), false);
  });

  it('treats values other than "1" as not disabled, like the hook', () => {
    const env: Record<string, string | undefined> = { HARNESS_DISABLE_WORKTREE_CLEANUP: 'true' };
    assert.equal(shouldCleanup('quit', env), true);
  });
});

describe('cleanupDisabledByEnv', () => {
  it('prefers the HARNESS_ knob and accepts either', () => {
    assert.equal(cleanupDisabledByEnv({ HARNESS_DISABLE_WORKTREE_CLEANUP: '1' }), true);
    assert.equal(cleanupDisabledByEnv({ CLAUDE_DISABLE_WORKTREE_CLEANUP: '1' }), true);
    assert.equal(cleanupDisabledByEnv({}), false);
  });
});