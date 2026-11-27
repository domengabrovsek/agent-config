---
name: worktree
description: "Creates an isolated git worktree for the current task, in this repo or a sibling repo with --repo, so the task never collides with the main checkout. Use when the user says '/worktree <slug>', '/worktree --repo <path> <slug>', or wants an isolated working copy for a new task."
---

Create a worktree for: $ARGUMENTS

## Slug

If $ARGUMENTS holds `--repo <path>`, take it out and follow [Another repo](#another-repo) after choosing the slug and branch. If $ARGUMENTS is still non-empty, treat the first argument as the slug.

If $ARGUMENTS is empty:

- If a plan file exists at `.claude/state/plans/<latest>.md` in the current project, derive slug from its basename (strip date prefix and `.md` extension).
- Else generate `<topic>-<6char-hex>` and report it.

The slug must be lowercase, hyphen-separated, no spaces.

## Branch type

Default to `feat/<slug>`. If the user's request looks like a bug fix, use `fix/<slug>`. For cleanups, `chore/<slug>`.

## Location

Worktrees live at `<repo-root>/.claude/worktrees/<slug>`, the directory Claude Code's `EnterWorktree` tool uses. Agent teammates with `isolation: "worktree"` land there too. The path sits inside the session's working directory, so the sandbox lets the session write to it.

## Steps

1. Find the repo root: `git rev-parse --show-toplevel`. Refuse if not inside a git repo.
2. Check that `git -C "<repo-root>" check-ignore -q .claude/worktrees/x` succeeds. If it fails, append `.claude/worktrees/` to `$(git rev-parse --git-common-dir)/info/exclude` now. Otherwise the main checkout lists every worktree as untracked.
3. If `<repo-root>/.claude/worktrees/<slug>` already exists, offer to enter it with `EnterWorktree` and `path` instead of creating a new one.
4. Create and enter the worktree with `EnterWorktree` and `name: "<slug>"`. It branches from `origin/<default-branch>` on a branch named `worktree-<slug>`, and moves the session into the worktree.
5. Move to the chosen branch name: `git switch --no-track -c "<branch>"`, then `git branch -D "worktree-<slug>"`. Do not use `git branch -m`: it rewrites `.git/config`, which the sandbox keeps read-only. The delete may warn that it cannot lock `.git/config`; the branch is still gone.
6. If step 2 had to add the exclude, also add `.claude/worktrees/` to `.gitignore` and commit it with the task. The exclude covers this clone only; the `.gitignore` entry covers every clone once it merges.
7. If `package-lock.json` exists, run `npm ci`. If only `package.json` exists, run `npm install --no-package-lock`, because `npm ci` needs a lockfile. The worktree holds only tracked files, and the push hooks need `node_modules`.
8. If `git config core.hooksPath` is `.husky/_` and `.husky/_` is missing, continue. The sandbox keeps `.husky` read-only, so the install cannot create it, and the commit and push gates copy it from the main worktree before the first commit.
9. Report the new working dir and branch name, then continue with the task.

A host without `EnterWorktree` creates the same layout itself: `git worktree add --no-track -b "<branch>" "<repo-root>/.claude/worktrees/<slug>" origin/<default-branch>`, then `cd` into it. Under the Claude Code sandbox, use `EnterWorktree` for the session's own repo. A sandboxed `git worktree add` fails on a base that tracks a protected path: `.husky`, or `.claude` settings, `hooks`, `skills`, `agents`, or `commands`. The `--repo` handoff runs in the user's terminal, outside the sandbox.

`EnterWorktree` also changes `$TMPDIR`, so a file written there before the switch is gone after it. Keep PR and comment bodies in the session scratchpad.

## Another repo

With `--repo <path>`, the worktree goes in that repo instead of the session's repo. This is the home repo flow: the home session plans, and a new session works in the sibling.

The sandbox lets a session write only its own worktree's `.git/worktrees/<name>`. A session cannot create, commit in, or switch a worktree of another repo, so it hands the task off.

Build this command for the user's own terminal:

```bash
wt="$(~/.agents/scripts/repo-worktree.sh "<path>" "<slug>" --branch "<branch>" --allow-protected)" && cd "$wt" && claude '<task prompt>'
```

- Write `<path>` as an absolute path, because the user's terminal has its own cwd.
- Add `--base <ref>` when the user names a base.
- Write the task prompt so a fresh session can start without this conversation. Open it by asking that session to install dependencies as in steps 7 and 8 above, because the new worktree has no `node_modules`.
- Single-quote the prompt and write each `'` inside as `'\''`, so the shell expands nothing.

Give the user the command and tell them to run it in a terminal, not with the `!` prefix, because `claude` needs its own terminal. Then stop. The command runs outside the sandbox, so it also checks out `.husky` and the `.claude` settings, `hooks`, `skills`, `agents`, and `commands`.

Never work around the sandbox for a sibling worktree. Do not run the script, clone the repo, use a sparse checkout, or commit there from this session.

## After creation

The worktree is its own working tree, so the session can change files without colliding with the main checkout.

When work is done:

- Open a PR from the worktree's branch as normal.
- After merge, run `/worktree-merge` to clean up the worktree and remove the local branch. A `--repo` worktree needs nothing: the SessionEnd cleanup hook prunes it after merge, outside the sandbox.
