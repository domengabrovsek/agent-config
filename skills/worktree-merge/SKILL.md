---
name: worktree-merge
description: "Cleans up a worktree after its branch has been merged: removes the worktree directory and deletes the local branch. Use when the user says '/worktree-merge' or asks to clean up a merged worktree."
---

Clean up the current worktree: $ARGUMENTS

## Preconditions

- Current `$PWD` must be inside a worktree (not the main checkout). Verify with `git rev-parse --git-dir != --git-common-dir`.
- The worktree's branch must be safely removable: merged into the default branch, or its upstream is `gone` and `git rev-list "$BRANCH" --not --remotes` prints nothing, or the user explicitly passes `--force`. A gone upstream alone does not prove the commits landed.
- Ignored files under the worktree's `.claude/state/` are deleted with it. Copy any the main checkout lacks into the main checkout's `.claude/state/` first.

If the branch is not safe to remove, stop and explain what's still pending (unpushed commits, open PR, etc.). Never auto-delete unmerged work.

## Steps

1. Capture worktree path and branch name:

   ```bash
   WORKTREE=$(git rev-parse --show-toplevel)
   BRANCH=$(git rev-parse --abbrev-ref HEAD)
   ```

2. If this session created the worktree with `EnterWorktree` and `name`, call `ExitWorktree` with `action: "remove"`. It returns the session to the main checkout and deletes both the worktree and its branch.
   - A squash-merged branch has commits that are not on the default branch, so the tool refuses. Retry with `discard_changes: true` only when the precondition check passed and `git status --porcelain` printed nothing.
   - Ask the user before discarding uncommitted files, even with `--force`.
   - `/worktree` renames the branch after creation, so the tool may leave it behind. If `git show-ref --verify --quiet "refs/heads/$BRANCH"` still succeeds, delete it with `git branch -d "$BRANCH"`, or `-D` once the precondition check passed.
3. Otherwise the worktree came from an earlier session, a teammate, or `EnterWorktree` with `path`, and `ExitWorktree` will not remove it:
   1. Call `ExitWorktree` with `action: "keep"` if this session entered it, else `cd "$(git rev-parse --git-common-dir)/.."`.
   2. Remove the worktree: `git worktree remove "$WORKTREE"`, adding `--force` only when `--force` was passed.
   3. Delete the local branch: `git branch -d "$BRANCH"` (or `-D` with `--force`).
   4. If the sandbox refuses to write `.git/worktrees/`, give the user both commands to run with the `!` prefix.
4. Report what was cleaned up.

## After cleanup

If the user has more work, suggest `/worktree <new-slug>` for the next task rather than mutating the main checkout.

## Merging parallel lanes

When several lane-mode teammates finish, merge their branches into the integration branch one at a time:

1. Review each teammate's diff for correctness.
2. Merge one branch. Resolve any conflict with `/resolve-conflicts` before merging the next.
3. After the last merge, run the full test suite, typecheck, and lint.
4. Prune the worktrees: `~/.agents/scripts/worktree-prune.sh --apply`. It removes only unlocked worktrees whose branch is merged, squash-merged, or upstream-gone with nothing unpushed, which is the post-merge state. Lane worktrees under `.claude/worktrees/` stay locked while their teammate runs, so they survive until it finishes.
