---
name: worktrees
description: "Audits and optionally prunes git worktrees: current repo by default, cross-repo scan under ~/dev/ with --all. Use when the user says '/worktrees', 'audit worktrees', or 'prune worktrees'."
---

Run worktree cleanup: $ARGUMENTS

## Modes

- **No flags**: single-repo dry-run against `$PWD`. Reports SAFE / KEEP verdicts and exits without changes.
- **`--apply`**: actually remove the SAFE worktrees and delete their local branches.
- **`--all`**: switch to cross-repo audit. Walks `~/dev/` (or `--root <path>`) up to 4 levels deep, finds every git repo, runs the same SAFE / KEEP report per repo. Combine with `--apply` for bulk removal.

## Implementation

Strip the `--all` flag from `$ARGUMENTS` and dispatch:

- If `--all` was passed: `~/.agents/scripts/worktree-prune.sh audit-all <remaining-args>`
- Otherwise: `~/.agents/scripts/worktree-prune.sh <args>`

## Safety rule

A worktree is "safe to remove" only if its branch is:

- **upstream-gone** (the remote branch was deleted, typically after PR merge), OR
- **merged into the repo's default branch** (`origin/HEAD` or `main`/`master`).

Locked worktrees are unlocked iff they pass the safety rule. Default-branch checkouts are never removed. Worktrees with unmerged commits or open PRs are kept.

## Tips

- Run `git fetch --prune origin` first to refresh remote-tracking branches. The script does NOT fetch automatically (network cost across many repos in `--all` mode). The `merged-into-default` check works offline.
- The `SessionEnd` hook runs the equivalent of `/worktrees --apply` opportunistically on session close, so manual invocation is rare for actively-used repos. Reach for `/worktrees --all` mostly for periodic cross-repo hygiene.
