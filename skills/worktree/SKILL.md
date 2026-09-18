---
name: worktree
description: "Creates an isolated git worktree for the current task and switches into it, resolving cross-session collisions before they happen. Use when the user says '/worktree <slug>' or wants an isolated working copy for a new task."
---

Create a worktree for: $ARGUMENTS

## Slug

If $ARGUMENTS is non-empty, treat the first argument as the slug.

If $ARGUMENTS is empty:

- If a plan file exists at `.claude/state/plans/<latest>.md` in the current project, derive slug from its basename (strip date prefix and `.md` extension).
- Else generate `<topic>-<6char-hex>` and ask the user to confirm.

The slug must be lowercase, hyphen-separated, no spaces.

## Branch type

Default to `feat/<slug>`. If the user's request looks like a bug fix, use `fix/<slug>`. For cleanups, `chore/<slug>`.

## Steps

1. Find the repo root: `git rev-parse --show-toplevel`. Refuse if not inside a git repo.
2. Compute target dir: `<repo-parent>/<repo-basename>-<slug>`. Refuse if it already exists (offer to `cd` into the existing one instead).
3. Create the worktree on a new branch:

   ```bash
   git worktree add "<target>" -b "<branch>"
   ```

4. `cd` into the worktree dir for all subsequent operations.
5. If `package-lock.json` exists, run `npm ci`. The worktree holds only tracked files, and the pre-push gate needs `node_modules`.
6. Show the user the new working dir, branch name, and confirm next steps.

## After creation

The worktree is its own working tree - the PreToolUse guard auto-bypasses inside it. The session can continue mutating files freely without colliding with the main checkout's session.

When work is done:

- Open a PR from the worktree's branch as normal.
- After merge, run `/worktree-merge` to clean up the worktree and remove the local branch.
