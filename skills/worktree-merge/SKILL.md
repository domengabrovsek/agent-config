---
name: worktree-merge
description: "Cleans up a worktree after its branch has been merged: removes the worktree directory and deletes the local branch, in this repo or any other. Use when the user says '/worktree-merge [<worktree-path>]' or asks to clean up a merged worktree."
---

Clean up a worktree: $ARGUMENTS

## Target

If $ARGUMENTS holds a path, the target is the worktree at that path, in any repo. Otherwise it is the worktree holding the current directory. Every git command below runs with `git -C`, so it works without `cd`.

## Preconditions

- The target must be a linked worktree, not a main checkout. Verify with `git -C "$WORKTREE" rev-parse --git-dir != --git-common-dir`.
- The worktree's branch must be safely removable: merged into the default branch, or its upstream is `gone` and `git rev-list "$BRANCH" --not --remotes` prints nothing, or the user explicitly passes `--force`. A gone upstream alone does not prove the commits landed.
- Ignored files under the worktree's `.claude/state/` are deleted with it. Copy any the main checkout lacks into the main checkout's `.claude/state/` first.

If the branch is not safe to remove, stop and explain what's still pending (unpushed commits, open PR, etc.). Never auto-delete unmerged work.

## Steps

1. Capture the worktree, its main checkout, and its branch. `TARGET` is the path argument, or `.` without one:

   ```bash
   WORKTREE=$(git -C "$TARGET" rev-parse --show-toplevel)
   MAIN=$(git -C "$WORKTREE" worktree list --porcelain | sed -n '1s/^worktree //p')
   BRANCH=$(git -C "$WORKTREE" branch --show-current)
   ```

2. If this session created the worktree with `EnterWorktree` and `name`, call `ExitWorktree` with `action: "remove"`. It returns the session to the main checkout and deletes both the worktree and its branch.
   - A squash-merged branch has commits that are not on the default branch, so the tool refuses. Retry with `discard_changes: true` only when the precondition check passed and `git status --porcelain` printed nothing.
   - Ask the user before discarding uncommitted files, even with `--force`.
   - `/worktree` renames the branch after creation, so the tool may leave it behind. If `git show-ref --verify --quiet "refs/heads/$BRANCH"` still succeeds, delete it with `git branch -d "$BRANCH"`, or `-D` once the precondition check passed.
3. Otherwise the worktree came from `/worktree --repo`, an earlier session, a teammate, or `EnterWorktree` with `path`, and `ExitWorktree` will not remove it:
   1. If this session entered it, call `ExitWorktree` with `action: "keep"`.
   2. Run `~/.agents/scripts/worktree-prune.sh --apply --repo "$MAIN"`. It removes the worktree and deletes its branch when the branch is merged, squash-merged, or upstream-gone with nothing unpushed. That covers `--repo` branches, which have no upstream. It also prunes the repo's other merged worktrees.
   3. If `git -C "$MAIN" worktree list` still shows `$WORKTREE`, report the verdict the script printed for it and stop.
   4. If the sandbox refuses to write `.git/worktrees/`, give the user the prune command to run with the `!` prefix.
4. Report what was cleaned up.

## After cleanup

If the user has more work, suggest `/worktree <new-slug>` for the next task rather than mutating the main checkout.

## Merging parallel lanes

When several lane-mode teammates finish, merge their branches into the integration branch one at a time:

1. Review each teammate's diff for correctness.
2. Merge one branch. Resolve any conflict with `/resolve-conflicts` before merging the next.
3. After the last merge, run the full test suite, typecheck, and lint.
4. Prune the worktrees: `~/.agents/scripts/worktree-prune.sh --apply`. It removes only unlocked worktrees whose branch is merged, squash-merged, or upstream-gone with nothing unpushed, which is the post-merge state. Lane worktrees under `.claude/worktrees/` stay locked while their teammate runs, so they survive until it finishes.
