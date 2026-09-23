---
name: plan
description: "Turns an approved spec into an implementation plan of vertical slices, each naming the acceptance criteria it closes, its tests, and its verify command. Use after a spec is approved, when the user says 'plan' or '/plan', or when build finds no plan."
---

Write an implementation plan for: $ARGUMENTS (default: the most recent approved spec in `.claude/state/specs/`)

## Workflow

**why-no-hook:** skill workflow guidance; each step requires understanding the surrounding context (repo, task shape, prior state).

1. **Read the spec**: its acceptance criteria, Seams, and Out of Scope. No spec and no approved grill outcome in the conversation? Run `/spec` first `(review-time: see section note)`
2. **Read the code the spec touches**: find and name the existing pattern each slice follows, the test runner, and the CI commands `(review-time: see section note)`
3. **Draft vertical slices** per `rules/engineering-principles.md`: `(review-time: see section note)`
   - Each slice cuts through every layer it needs and is verifiable on its own `(review-time: see section note)`
   - Each slice names the criteria it closes. A prefactor slice closes none and goes first `(review-time: see section note)`
   - Each slice names its tests first: one test per `test` criterion, at the spec's seams `(review-time: see section note)`
   - Each slice fits one fresh context window and about 100 to 300 changed lines `(review-time: see section note)`
4. **Check coverage**: every automated criterion maps to exactly one slice. A criterion with no slice, or a slice with no criterion and no prefactor reason, is a plan defect `(review-time: see section note)`
5. **Group lanes**: slices that touch disjoint files form separate lanes for `rules/parallel-agents.md`. Slices that share a file stay in one lane, in order `(review-time: see section note)`
6. **Save** to `.claude/state/plans/YYYY-MM-DD-<topic>.md` `(review-time: see section note)`
7. **Hand off**: an approved spec already approved the scope, so continue to `/build` without asking. Stop and ask only for an architectural choice the spec left open, one question at a time `(review-time: see section note)`

## Plan format

```markdown
---
spec: .claude/state/specs/<spec file>
branch: <feature branch>
---
# Plan: <title>

## Slices

### 1. <name> (closes AC-1, AC-2)
- Pattern: <existing code this follows, file:line>
- Files: <paths>
- Tests first: <file>::<name> for AC-1, <file>::<name> for AC-2
- Verify: <command>
- Lane: A

## Coverage

| AC | Slice |
| --- | --- |
| AC-1 | 1 |

## Risks
- <What could invalidate the plan, and the signal that shows it>
```
