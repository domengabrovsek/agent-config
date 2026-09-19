---
name: constraints
description: "Establishes a repo's quality bar as CONSTRAINTS.md: numbers with a command behind each, ratcheted so they never regress, guarded against quiet weakening. Use when no quality bar is written down, when the user says 'set up constraints' or 'define our standards', or when an agent keeps silencing checks or skipping tests to reach green."
---

> Source: [addyosmani/agent-skills - skills/constraint-driven-development](https://github.com/addyosmani/agent-skills/tree/main/skills/constraint-driven-development), adapted.

# Constraints

Prose standards do not survive the end of a session. This skill produces a written record of this repo's bar, with numbers, that can be checked mechanically.

The interview needs a live user. In a non-interactive context (CI, `/loop`, autonomous runs), apply only the floor, note that you did, and flag the rest for a human.

## Process

### 1. Detect before you ask

Never ask what you can read. Check `package.json`, the test runner and its coverage output, `eslint.config.*` or `biome.json`, `.github/workflows/`, and `.claude/`. Report what you found in two lines, then ask only what is left.

### 2. Four questions, each with a default

Follow the one-question-per-turn discipline from `rules/communication.md`. Every question has a default, so "I don't know" still produces a working config. Stop at four.

```text
Q1: Beyond the floor, which of these do you want enforced?
    (a) coverage on new code  (b) security scanning  (c) performance budgets
    (d) accessibility  (e) architecture boundaries
GUESS: (a) and (b). DEFAULT if unsure: (a) and (b).
Note the cost: (c) and (d) need a running URL, (e) needs a rules file.

Q2: When a check fails mid-task, block or warn?
GUESS: block. DEFAULT: block on the floor, warn on the rest for two weeks.

Q3: Target numbers in mind, or measure today and hold the line?
GUESS: measure. DEFAULT: measure and hold (see Ratchets).

Q4: Slowest check you will tolerate before the agent hands work back?
GUESS: about 90 seconds. DEFAULT: 90s at task end, unlimited in CI.
```

### 3. Write CONSTRAINTS.md

One file at the repo root, so any agent can read it and a change to it shows up in review.

```markdown
# Constraints

## Floor (always enforced, no setup required)

- No new suppression comments: `@ts-ignore`, `eslint-disable`, `biome-ignore`
- No unimplemented stubs, no empty `catch {}`
- No skipped or deleted tests without a reason in the commit message
- No secrets in source
- This file does not get weakened to make a change pass

## Enforced with numbers

| Dimension | Rule | Checked by | Runs at |
| --- | --- | --- | --- |
| Types | Zero type errors | `tsc --noEmit` | every edit |
| Lint | Zero errors | `biome check` | every edit |
| Secrets | No secrets in source | `gitleaks detect --redact` | every edit |
| Coverage | Changed lines >= 80% covered | test runner coverage + git diff | task end, CI |
| Deps | Nothing at high or above | `osv-scanner scan source -r .` | CI |

## Measured, not yet enforced

| Metric | Today | Direction |
| --- | --- | --- |
| Project coverage | 62.4% | must not fall |
| Bundle size (main) | 184 kB | must not grow |

## Exceptions

| ID | Rule | Path | Reason | Owner | Expires |
| --- | --- | --- | --- | --- | --- |
```

Every row names the command that produces the verdict. A dimension with a number and no command is an aspiration, not a constraint. Add one line to the repo's `CLAUDE.md`, or to `AGENTS.md` when the repo has no `CLAUDE.md`: read `CONSTRAINTS.md` before writing code; never weaken it to make a change pass.

### 4. Install what each dimension needs

Use the de facto tool per dimension, never a hand-rolled checker: `tsc`, the existing linter, the existing test runner's coverage, `semgrep`, `gitleaks`, `osv-scanner`, `size-limit`, `dependency-cruiser`. Four traps:

- `--redact` on gitleaks is mandatory; report the rule and location, never the matched value.
- Lighthouse and axe need a running URL. No URL means drop the dimension, not fake the check.
- Scope expensive scans to the diff; a whole-repo mutation run gets turned off.
- Coverage reads the lcov the suite already writes; never run the suite twice for a number.

Wrap the commands in repo scripts (`check:fast` per edit, `check:task` at task end, `check:full` in CI). `CONSTRAINTS.md` stays the canonical source; if the scripts drift, the file wins.

### 5. Wire it to the lifecycle

Running everything everywhere is the failure mode: a check that stalls the loop gets switched off. Cost decides placement: types, lint, and secrets per edit; related tests and changed-line coverage at task end (`/verify-done`); everything else in CI. Scope to the diff: coverage of changed lines is a number the agent can move, project coverage is one it inherited.

### 6. Guard the bar itself

An agent hitting a red check takes the cheapest road to green. Watch the diff for five moves: a threshold lowered in `CONSTRAINTS.md`, a test made easier (`.skip`, deleted test file, assertion removed), a silenced checker (new suppression comment), unfinished work (stub, empty catch), a new Exceptions row nobody discussed. Tightening is silent; loosening is loud.

[scripts/floor-guard.mjs](scripts/floor-guard.mjs) is the reference implementation: diff-scoped against a base ref, exit 0 clean, 1 violation, 2 could-not-run. Copy it into the target repo (or run it from this skill's directory) at review time or as a repo-local pre-push hook. Wire it per repo; it is not a global hook. Adapt the three regexes per ecosystem; keep the contract identical.

Rank checks by one question: can the agent make this pass with code that does not work?

- **External**: axe, osv-scanner, Lighthouse. The agent cannot argue with these.
- **Project**: your lint rules and layer boundaries. A human owns the file.
- **Suite**: your own tests. Useful, and the only genuinely circular one.

At least one constraint must be external `(review-time: circularity is a judgment about who authored the check)`

### 7. Ratchets, when there is no number

Setting 80% coverage on a codebase at 62% buys a permanently red build. Instead record today's value and a direction: every check compares against the recorded number, never an aspiration. When a number improves, update it; when it drops, that is the finding.

## Sane defaults

| Constraint | Default |
| --- | --- |
| Coverage of changed lines | >= 80% |
| Project coverage | today's value, must not fall |
| Dependency vulnerabilities | nothing at high or above |
| Exception lifetime | 90 days |
| Ratchet tolerance | 0.5% |

State the number and the reason together. A threshold without a rationale gets deleted by the next person who hits it.
