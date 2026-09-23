/**
 * worktree-cleanup - pi's translation of the Claude worktree-cleanup hook.
 *
 * On session teardown (every reason except reload), opportunistically prune
 * safely-disposable git worktrees in the session cwd by invoking
 * scripts/worktree-prune.sh --apply - the same conservative oracle Claude
 * uses: only upstream-gone or merged-into-default branches go, locked
 * worktrees ride inside its safety verdicts, uncertain entries stay.
 *
 * Fully silent by design: the prune is advisory, shutdown-time UI does not
 * render, and scripted pi runs must not gain prune chatter. Dry-run
 * visibility lives in the script itself (`worktree-prune.sh` without
 * --apply) and the worktrees skill. Disable per-session with
 * HARNESS_DISABLE_WORKTREE_CLEANUP=1, or the legacy CLAUDE_ spelling.
 *
 * Module top imports only node builtins so `node --test` can exercise the
 * pure predicate without resolving pi packages; the factory resolves
 * @earendil-works/pi-coding-agent dynamically at runtime.
 */

import { execFileSync } from 'node:child_process';
import { existsSync, realpathSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';

/* ---------------------------------------------------------------------------
 * Pure decision predicate
 * --------------------------------------------------------------------------- */

export type ShutdownReason = 'quit' | 'reload' | 'new' | 'resume' | 'fork';

export const CLEANUP_ENV_DISABLE = 'HARNESS_DISABLE_WORKTREE_CLEANUP';
export const CLEANUP_ENV_DISABLE_LEGACY = 'CLAUDE_DISABLE_WORKTREE_CLEANUP';

/** The knob is on only for an exact "1", matching the Claude hook. */
export function cleanupDisabledByEnv(env: Record<string, string | undefined>): boolean {
  return env[CLEANUP_ENV_DISABLE] === '1' || env[CLEANUP_ENV_DISABLE_LEGACY] === '1';
}

/** Cleanup runs on real session ends, never reload, unless disabled. */
export function shouldCleanup(reason: ShutdownReason, env: Record<string, string | undefined>): boolean {
  if (reason === 'reload') return false;
  return !cleanupDisabledByEnv(env);
}

/* ---------------------------------------------------------------------------
 * Extension wiring
 * --------------------------------------------------------------------------- */

export default async function (pi: ExtensionAPI) {
  const { getAgentDir } = await import('@earendil-works/pi-coding-agent');

  pi.on('session_shutdown', (event, ctx) => {
    if (!shouldCleanup(event.reason, process.env)) return;

    let moduleDir: string;
    try {
      moduleDir = dirname(realpathSync(fileURLToPath(import.meta.url)));
    } catch {
      moduleDir = dirname(fileURLToPath(import.meta.url));
    }
    /* Same layout assumption as the other extensions: the script lives under
     * <checkout>/scripts; the agent-dir path covers standalone installs. */
    const candidates = [
      join(moduleDir, '../../scripts/worktree-prune.sh'),
      join(getAgentDir(), 'scripts/worktree-prune.sh'),
    ];
    const scriptPath = candidates.find((candidate) => existsSync(candidate));
    if (scriptPath === undefined) return; // hook parity: [ -x ... ] || exit 0

    try {
      /* Synchronous like the Claude hook: the prune (fast, conservative)
       * completes before the process exits instead of dying mid-prune. */
      execFileSync('bash', [scriptPath, '--apply', '--repo', ctx.cwd], { timeout: 30_000, stdio: 'ignore' });
    } catch {
      // Advisory only: prune failures never block shutdown (hook parity).
    }
  });
}