# State Persistence

**When to apply:** reading or writing research, specs, plans, run files, or session diaries.

Workflow state lives untracked under `.claude/state/`: `research/`, `specs/`, `plans/`, `sessions/`, `wayfinder/`, and `runs/<branch-slug>/`.

## Rules

- State lives in the target repo, not the session cwd. The target is `git -C <path> rev-parse --show-toplevel`, where `<path>` holds the code being changed. A home repo's own state holds only work on the home repo `(review-time: a skill picks its path before any hook runs)`
- Write and read with absolute paths under the target's main checkout, which hooks search first: `STATE="$(dirname "$(git -C <path> rev-parse --path-format=absolute --git-common-dir)")/.claude/state"` `(review-time: a skill picks its path before any hook runs)`
- Create a directory before writing to it `(review-time: simple ops choice)`
- Name files `YYYY-MM-DD-descriptive-name.md` `(review-time: a filename hook would flag many existing files)`
- End each session with real work with a diary in `sessions/` `(review-time: subjective threshold "real work")`
- Check the target repo's state for past work before new research `(review-time: workflow guidance)`
