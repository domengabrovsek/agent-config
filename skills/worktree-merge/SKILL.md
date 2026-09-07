---
name: worktree-merge
description: "Cleans up a worktree after its branch has been merged: removes the worktree directory and deletes the local branch. Use when the user says '/worktree-merge' or asks to clean up a merged worktree."
---

Clean up the current worktree: $ARGUMENTS

## Preconditions

- Current `$PWD` must be inside a worktree (not the main checkout). Verify with `git rev-parse --git-dir != --git-common-dir`.
- The worktree's branch must be safely removable: either merged into the default branch upstream, or its upstream is `gone` (PR was merged and remote branch deleted), or the user explicitly passes `--force`.

If the branch is not safe to remove, stop and explain what's still pending (unpushed commits, open PR, etc.). Never auto-delete unmerged work.

## Steps

1. Capture worktree path and branch name:

   ```bash
   WORKTREE=$(git rev-parse --show-toplevel)
   BRANCH=$(git rev-parse --abbrev-ref HEAD)
   ```

2. Move out of the worktree to the main checkout (`cd "$(git rev-parse --git-common-dir)/.."`).
3. Remove the worktree: `git worktree remove "$WORKTREE"`. If it has uncommitted changes and `--force` was passed, use `git worktree remove --force "$WORKTREE"`.
4. Delete the local branch: `git branch -d "$BRANCH"` (or `-D` with `--force`).
5. Report what was cleaned up.

## After cleanup

If the user has more work, suggest `/worktree <new-slug>` for the next task rather than mutating the main checkout.

## Merging parallel lanes

When several lane-mode teammates finish, merge their branches into the integration branch one at a time:

1. Review each teammate's diff for correctness.
2. Merge one branch. Resolve any conflict by hand before merging the next - never spawn an agent for conflict resolution.
3. After the last merge, run the full test suite, typecheck, and lint.
4. Prune the worktrees: `~/.agents/scripts/worktree-prune.sh --apply`. It removes only worktrees whose branch is upstream-gone or merged into the default, which is the post-merge state. Anything still active survives.
