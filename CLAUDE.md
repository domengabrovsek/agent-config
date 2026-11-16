# This repo

This checkout is the live agent config, because `~/.claude` links into it. The sandbox keeps its `hooks`, `rules`, `skills`, `settings.json`, and `AGENTS.md` read-only to Bash, so git commands that rewrite them fail halfway in the main checkout.

- Make every change in a worktree under `.claude/worktrees/`, created with `/worktree`. Never switch branches, stash, or pull in the main checkout.
- Leave the main checkout on `main`. The `config-autoupdate.sh` hook fast-forwards it at session start, after the user merges.
