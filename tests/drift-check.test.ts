/**
 * Tests for drift-check: pure summarization of `setup-hosts.sh --check`
 * output with a fake runner. No integration test runs the real script - on a
 * fresh CI checkout it always reports missing links, coupling tests to the
 * environment.
 */

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { isIssueRow, summarizeCheckResult } from '../pi/extensions/drift-check.ts';

const CONVERGED_STDOUT = [
  'PATH                               STATE         DETAIL',
  '----                               -----         ------',
  '~/.claude/settings.json            OK            already correct',
  '~/.pi/agent/extensions             OK            already correct',
  '',
  'All selected host configuration is current.',
].join('\n');

const DRIFTED_STDOUT = [
  'PATH                               STATE         DETAIL',
  '----                               -----         ------',
  '~/.claude/CLAUDE.md                OK            already correct',
  '~/.claude/pull_request_template.md OK already correct',
  '~/.claude/settings.json            MISSING       no such file or directory',
  '~/.claude/skills                   CONFLICT      path exists and is not a symlink',
  '~/.agents/skills                   WRONG-LINK    links elsewhere',
].join('\n');

const DRIFTED_STDERR = '3 selected configuration issue(s) remain.\n';

describe('isIssueRow', () => {
  it('keeps data rows whose state is not OK', () => {
    assert.ok(isIssueRow('~/.claude/settings.json   MISSING   no such file or directory'));
    assert.ok(isIssueRow('~/.claude-personal/agent/settings.json MISSING-SRC /x/settings.json'));
    assert.ok(isIssueRow('codex/hooks.json                   STALE         registry events changed'));
  });

  it('skips OK rows even when column padding collapses to single spaces', () => {
    assert.ok(!isIssueRow('~/.claude/pull_request_template.md OK already correct'));
    assert.ok(!isIssueRow('~/.claude/settings.json            OK            already correct'));
  });

  it('skips the header, separator, OK rows, and blanks', () => {
    assert.ok(!isIssueRow('PATH                               STATE         DETAIL'));
    assert.ok(!isIssueRow('----                               -----         ------'));
    assert.ok(!isIssueRow('~/.claude/settings.json            OK            already correct'));
    assert.ok(!isIssueRow(''));
  });
});

describe('summarizeCheckResult', () => {
  it('reports clean on exit zero regardless of output', () => {
    const summary = summarizeCheckResult({ code: 0, stdout: CONVERGED_STDOUT, stderr: '' });
    assert.deepEqual(summary, { clean: true, issueCount: 0, sample: [] });
  });

  it('parses the issue count from stderr and samples the first offending rows', () => {
    const summary = summarizeCheckResult({ code: 1, stdout: DRIFTED_STDOUT, stderr: DRIFTED_STDERR });
    assert.equal(summary.clean, false);
    assert.equal(summary.issueCount, 3);
    assert.deepEqual(summary.sample, [
      '~/.claude/settings.json  MISSING  no such file or directory',
      '~/.claude/skills  CONFLICT  path exists and is not a symlink',
      '~/.agents/skills  WRONG-LINK  links elsewhere',
    ]);
  });

  it('falls back to the offending-row count when stderr is unparseable', () => {
    const summary = summarizeCheckResult({ code: 1, stdout: DRIFTED_STDOUT, stderr: '' });
    assert.equal(summary.issueCount, 3);
  });

  it('reports a null count when the failure carries no table and no summary', () => {
    const summary = summarizeCheckResult({ code: 2, stdout: '', stderr: 'Choose --check or --apply.' });
    assert.equal(summary.clean, false);
    assert.equal(summary.issueCount, null);
    assert.deepEqual(summary.sample, []);
  });
});