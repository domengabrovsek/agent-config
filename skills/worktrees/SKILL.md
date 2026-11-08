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

- **merged into the repo's default branch** (`origin/HEAD` or `main`/`master`), OR
- **squash-merged**: the branch tip is not an ancestor, but merging it into the default branch produces the default branch unchanged, OR
- **upstream-gone** (the remote branch was deleted) with every commit reachable from the default branch or a remote. A gone upstream with unpushed commits is kept.

A lock marks a worktree in use, so locked worktrees are kept (reason `locked`). Pass `--force-locked` to judge them on their branch, unlock the safe ones, and re-lock any whose removal fails. Default-branch checkouts are never removed. Worktrees with unmerged commits or open PRs are kept.

Before removal, the script copies ignored files under the worktree's `.claude/state/` into the main checkout. When the main checkout holds a same-named file with other content, it keeps the worktree and reports the file. Branches go with `git branch -d`, or `-D` only after the commit check above passes. `--min-idle <minutes>` also keeps worktrees whose index or HEAD changed recently.

## Tips

- Run `git fetch --prune origin` first to refresh remote-tracking branches. The script does NOT fetch automatically (network cost across many repos in `--all` mode). The `merged-into-default` check works offline.
- The `SessionEnd` hook runs the equivalent of `/worktrees --apply --min-idle 30` opportunistically on session close, so manual invocation is rare for actively-used repos. Reach for `/worktrees --all` mostly for periodic cross-repo hygiene.
