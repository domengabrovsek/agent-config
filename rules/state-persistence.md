# State Persistence

**When to apply:** when saving research artifacts, specs, plans, or session diaries.

All work artifacts must be saved to the project-level `.claude/state/` directory so they persist across sessions and machines.

## Directories

- `.claude/state/research/` - research artifacts from the research phase `(review-time: descriptive, not a rule)`
- `.claude/state/specs/` - specification documents from the /spec skill `(review-time: descriptive, not a rule)`
- `.claude/state/plans/` - implementation plans from the grill or `/plan` `(review-time: descriptive, not a rule)`
- `.claude/state/sessions/` - session diary entries from `/summarize` `(review-time: descriptive, not a rule)`
- `.claude/state/runs/<branch-slug>/` - per-branch run files `(review-time: descriptive, not a rule)`

## Rules

- Create `.claude/state/` directories if they don't exist before writing `(review-time: simple ops choice, no enforcement value-add)`
- Use naming convention: `YYYY-MM-DD-descriptive-name.md` (e.g., `2026-03-12-research-auth-refactor.md`) `(review-time: a filename-pattern hook is possible but very high false-positive rate on existing files)`
- Every session with real work should end with a summary saved to `.claude/state/sessions/` `(review-time: subjective threshold "real work")`
- Plans and research are per-project, not global `(review-time: location preference)`
- Check `.claude/state/` for relevant past work before starting new research `(review-time: workflow guidance)`
