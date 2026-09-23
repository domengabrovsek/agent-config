---
name: build
description: "Implements code incrementally with quality gates. Use when the user says 'build' or 'implement', or when starting the implementation phase of an approved plan."
---

Implement the approved plan incrementally: $ARGUMENTS

Follow these disciplines:

## Before Starting

**why-no-hook:** skill workflow guidance; each step requires understanding the surrounding context (repo, task shape, prior state).

- Verify an approved plan exists (in `.claude/state/plans/` or the current conversation) `(review-time: see section note)`
- If no plan exists, stop and ask the user to run /plan first `(review-time: see section note)`
- Read the plan and identify the task list `(review-time: see section note)`
- Copy the task list to `.claude/state/runs/<branch-slug>/tasks.md` and tick each task as it finishes. Read that file, not memory, to resume after compaction `(review-time: see section note)`
- If a spec drives the plan, set its `branch:` frontmatter to the current branch `(review-time: see section note)`
- Load relevant expert agents based on the plan's domain (see `rules/agent-routing.md`) - their guardrails apply to every increment `(review-time: see section note)`
- If the plan has 2+ file-isolated lanes, execute it in **lane mode** - spawn one lane-mode teammate per lane (see `rules/parallel-agents.md`); single-lane plans stay in this session `(review-time: lane-vs-single judgment from the plan shape)`

## Increment Rules

For each task in the plan:

1. **Ask**: "What is the simplest thing that could work?" `(review-time: see section note)`
2. **Scope**: touch only what the task requires - no drive-by refactors, no "while I'm here" changes `(review-time: see section note)`
3. **Follow `rules/engineering-principles.md`**: vertical slicing, change sizing (~100 lines per commit, max 300, split at 1000+), and anti-rationalization rules all apply `(review-time: see section note)`
4. **Compile continuously**: the project must build after every increment. Run typecheck after each file change. `(review-time: see section note)`
5. **Test alongside**: write tests as part of the increment, not as a separate step afterward `(review-time: see section note)`
6. **Checkpoint**: after completing each task: `(review-time: see section note)`
   - Run `/verify-done` (typecheck + lint + tests + build) - do not rely on post-edit hooks alone `(review-time: see section note)`
   - If all pass, commit with a conventional commit message `(review-time: see section note)`
   - If any fail, fix before moving to the next task - never accumulate errors across tasks `(review-time: see section note)`

## Slice Loop

When a plan slice lists **Tests first**, run it as a loop with separate roles. The agent that writes code never writes or grades its own tests.

1. **Tests**: a `QA Expert` subagent writes the slice's tests at the spec's seams and runs them. Each must fail for the expected reason. It commits them as `test(...)` and appends their paths to `.claude/state/runs/<branch-slug>/tests.lock` `(review-time: see section note)`
2. **Implement**: the domain persona from `rules/agent-routing.md`, or this session for a single lane, makes the tests pass. `hooks/pre-edit-test-lock.sh` blocks edits to locked tests. A test it believes is wrong goes back to the `QA Expert` with the reason. Checkpoint as above `(review-time: see section note)`
3. **Review panel**: in one message, spawn read-only reviewers on the slice diff: `PR Reviewer`, `Cybersecurity Expert`, and `Spec Verifier` for the slice's criteria. Add `GDPR Expert`, `UX Expert`, or `PostgreSQL Expert` when the diff touches their domain `(review-time: see section note)`
4. **Verify findings**: check each blocker and issue against the code or a reproduction before accepting it. Drop a finding with no file and line or no evidence `(review-time: see section note)`
5. **Fix**: the implementer fixes accepted code findings, and the `QA Expert` fixes test findings. Checkpoint `(review-time: see section note)`
6. **Re-review**: the same panel reviews the fix diff. The slice is done when the panel returns no blockers or issues and the Spec Verifier passes `(review-time: see section note)`

Budget: three review rounds per slice. Escalate under **Blocked on me** when the cap is hit, the same failure repeats twice, or a finding invalidates the plan. Log each round in `tasks.md` `(review-time: see section note)`

## Finishing

- After the last task, spawn the `Spec Verifier` when a spec matches the branch. Fix each FAIL and re-run it until every automated criterion passes at HEAD `(review-time: see section note)`
- End the run with three headings: **Blocked on me** (including manual criteria), **Changed**, **Found** `(review-time: see section note)`

## Feature Flags

If the feature is large and will take multiple sessions:

- Use a feature flag to keep incomplete work behind a toggle `(review-time: see section note)`
- Each increment should be independently mergeable (behind the flag) `(review-time: see section note)`
- The flag is removed only when the full feature is complete and tested `(review-time: see section note)`

## Completion

After all tasks are done:

- Run `/verify-done` one final time `(review-time: see section note)`
- Summarize what was built and what changed `(review-time: see section note)`
- Flag any deferred items or follow-up work as issues `(review-time: see section note)`
