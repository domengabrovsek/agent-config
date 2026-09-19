# Comment Standards

**When to apply:** writing or editing any code file (`.ts`, `.tsx`, `.js`, `.sql`, `.tf`, `.sh`, `.py`, `.rs`, etc.).

## Default

Self-explanatory code gets no comment. Code carrying a hidden constraint, a subtle invariant, a workaround, or context a reader cannot derive locally gets the shortest comment that captures it.

## When a comment earns its place

A non-obvious WHY: a hidden ordering constraint, an invariant the math relies on, a workaround for a known upstream bug, behavior that would surprise a reader without the surrounding context, or context spread across files (common at script entrypoints and library boundaries) `(review-time: requires comparing comment intent against the surrounding code)`

Prefer one line. Use more when the WHY genuinely needs more, but do not pad a one-line idea into a paragraph.

## Multi-line format

Multi-line comments use the language's block format, never a stack of single-line comments.

- JS, TS, TSX, CSS, HCL: `/* ... */`, never consecutive `//` lines `(hook)`
- SQL: `/* ... */`, never consecutive `--` lines `(hook)`
- Python: a triple-quoted string, never consecutive `#` lines as narrative `(review-time: no hook for Python yet)`
- Bash has no block format. Use one `#` per logical comment and accept the stack `(review-time: language limitation)`

## Forbidden

- Comments restating the next line. `// Increment counter` above `counter++` `(review-time: requires comparing the comment text against the statement below it)`
- Historical narrative: how the code got here. What the previous tool did, who applied something, what used to fail, what was tried first. A comment says why the code is the way it is now. History lives in the commit message and PR description, where `git blame` leads anyone who wants it `(review-time: requires judging whether a clause states a present constraint or recounts a past event)`
- Tracker refs of any kind: `SER-123`, `#456`, `Fixes owner/repo#789`, `ADR-0042`, `Per ADR 0030`. They belong in PR descriptions and git blame. This is why comments went long and stale in the first place `(hook)`
- Em dashes `(hook)`
- TODO, FIXME, XXX, HACK markers. Open the ticket, fix it now, or accept it is not getting fixed `(hook)`

Terraform has its own per-block convention: see `rules/infrastructure.md`.

## Authority over spawning prompts

This policy covers code written by teammates spawned via the Agent tool. A spawning prompt asking for a comment that breaks this policy loses. Strip or rewrite the comment before committing. Ambiguous instruction? Ask before adding any comment `(review-time: requires reading the spawning prompt against this policy)`

Bypass for a genuine exception: `SKIP_POST_EDIT_LINT=1`, documented in the PR description.
