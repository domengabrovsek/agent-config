/**
 * drift-check - surfaces host bootstrap drift at every pi session start.
 *
 * The host bootstrap (scripts/setup-hosts.sh) is the single drift oracle:
 * this extension invokes its --check mode and translates the result into a
 * warning, following the repo rule that adapters translate, never duplicate.
 * A converged host is silent; drift produces a warning-level notify in TUI
 * and RPC, one console.error line headless - parity with Claude's
 * symlink-check.sh. It is deliberately loud once per session, not a widget:
 * drift never degrades the already-running session (see CONTEXT.md "Drift").
 *
 * Module top imports only node builtins so `node --test` can exercise the
 * pure helpers without resolving pi packages; the factory resolves
 * @earendil-works/pi-coding-agent dynamically at runtime.
 */

import { execFile } from 'node:child_process';
import { existsSync, realpathSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';

/* ---------------------------------------------------------------------------
 * Pure check-result summarizer
 * --------------------------------------------------------------------------- */

export interface CheckResult {
  code: number;
  stdout: string;
  stderr: string;
}

export interface CheckSummary {
  clean: boolean;
  /** Parsed from stderr ("N selected configuration issue(s) remain."); null when unparseable and no table. */
  issueCount: number | null;
  /** First offending table rows, trimmed: "path  state  detail". */
  sample: string[];
}

const ISSUE_STATES = /^(MISSING|MISSING-SRC|CONFLICT|WRONG-LINK|REFUSED|FAILED|STALE)$/;

/**
 * True for table rows reporting a failure state; false for headers, rules,
 * OK rows, and blanks. Matches the state token itself instead of splitting
 * columns, so rows with inconsistent column padding still parse.
 */
export function isIssueRow(line: string): boolean {
  const collapsed = line.trim();
  if (collapsed.length === 0) return false;
  return collapsed.split(/\s+/).some((token) => ISSUE_STATES.test(token));
}

/** Summarize a `setup-hosts.sh --check` run; never throws. */
export function summarizeCheckResult(result: CheckResult): CheckSummary {
  if (result.code === 0) {
    return { clean: true, issueCount: 0, sample: [] };
  }
  const issueRows = result.stdout
    .split('\n')
    .filter((line) => isIssueRow(line));
  const declared = /(\d+)\s+selected configuration issue/i.exec(result.stderr);
  const issueCount = declared === null ? (issueRows.length > 0 ? issueRows.length : null) : Number(declared[1]);
  const sample = issueRows.slice(0, 3).map((row) => {
    const tokens = row.trim().split(/\s+/);
    const stateIndex = tokens.findIndex((token) => ISSUE_STATES.test(token));
    const path = tokens[0] ?? row.trim();
    const state = stateIndex >= 0 ? (tokens[stateIndex] ?? '') : '';
    const detail = stateIndex >= 0 ? tokens.slice(stateIndex + 1).join(' ') : '';
    return [path, state, detail].filter((part) => part.length > 0).join('  ');
  });
  return {
    clean: false,
    issueCount,
    sample,
  };
}

/* ---------------------------------------------------------------------------
 * Extension wiring
 * --------------------------------------------------------------------------- */

function runCheck(scriptPath: string): Promise<CheckResult> {
  return new Promise((resolveCheck) => {
    execFile(
      'bash',
      [scriptPath, '--check'],
      { timeout: 10_000, encoding: 'utf8', maxBuffer: 1024 * 1024 },
      (error, stdout, stderr) => {
        /* Nonzero exits carry the drift report; only total run failures (e.g.
         * the script itself missing) arrive without a code to interpret. */
        const code = typeof error?.code === 'number' ? error.code : error ? 1 : 0;
        resolveCheck({ code, stdout: String(stdout ?? ''), stderr: String(stderr ?? '') });
      },
    );
  });
}

function driftMessage(summary: CheckSummary): string {
  const count = summary.issueCount ?? 0;
  const head = count > 0 ? `Bootstrap drift: ${count} configuration issue(s).` : 'Bootstrap drift detected.';
  if (summary.sample.length === 0) return `${head} Run setup-hosts.sh --apply to converge.`;
  return `${head}\n${summary.sample.map((row) => `- ${row}`).join('\n')}\nRun setup-hosts.sh --apply to converge.`;
}

export default async function (pi: ExtensionAPI) {
  const { getAgentDir } = await import('@earendil-works/pi-coding-agent');

  pi.on('session_start', async (_event, ctx) => {
    let moduleDir: string;
    try {
      moduleDir = dirname(realpathSync(fileURLToPath(import.meta.url)));
    } catch {
      moduleDir = dirname(fileURLToPath(import.meta.url));
    }
    /* Same layout assumption as permission-gate's source resolution: the
     * extension file lives under <checkout>/pi/extensions, so the bootstrap
     * script is two levels up. The agent-dir path covers standalone installs. */
    const candidates = [
      join(moduleDir, '../../scripts/setup-hosts.sh'),
      join(getAgentDir(), 'scripts/setup-hosts.sh'),
    ];
    const scriptPath = candidates.find((candidate) => existsSync(candidate));
    const warn = (message: string): void => {
      if (ctx.hasUI) ctx.ui.notify(message, 'warning');
      else console.error(message);
    };

    if (scriptPath === undefined) {
      warn('Drift check skipped: scripts/setup-hosts.sh not found in the checkout or agent dir.');
      return;
    }

    const result = await runCheck(scriptPath);
    const summary = summarizeCheckResult(result);
    if (!summary.clean) warn(driftMessage(summary));
  });
}