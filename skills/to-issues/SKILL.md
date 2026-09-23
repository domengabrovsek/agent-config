---
name: to-issues
description: "Breaks a plan, spec, or PRD into independently-grabbable issues on the project issue tracker using tracer-bullet vertical slices. Use when the user wants to convert a plan into issues, create implementation tickets, or break down work into issues."
---

> Source: [mattpocock/skills - engineering/to-tickets](https://github.com/mattpocock/skills/tree/main/skills/engineering/to-tickets)

# To Issues

Break a plan into independently-grabbable issues using vertical slices (tracer bullets).

Target the project's issue tracker directly - GitHub via `gh` or Jira via `acli`, per `rules/git-conventions.md` and the `jira` skill. Use whatever label the tracker already uses to mark agent-ready work.

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes an issue reference (issue number, URL, or path) as an argument, fetch it from the issue tracker and read its full body and comments.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Issue titles and descriptions should use the project's domain glossary vocabulary, and respect ADRs in the area you're touching.

Look for opportunities to prefactor the code to make the implementation easier - "make the change easy, then make the easy change." Any prefactoring should be its own issue, sequenced first. `(review-time: see section note)`

### 3. Draft vertical slices

**why-no-hook:** skill workflow guidance; each step requires understanding the surrounding context (repo, task shape, prior state).

Break the plan into **tracer bullet** issues. Each issue is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

Slices may be 'HITL' or 'AFK'. HITL slices require human interaction, such as an architectural decision or a design review. AFK slices can be implemented and merged without human interaction. Prefer AFK over HITL where possible.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests) `(review-time: see section note)`
- A completed slice is demoable or verifiable on its own `(review-time: see section note)`
- Each slice is sized to fit in a single fresh context window `(review-time: see section note)`
- Prefer many thin slices over few thick ones `(review-time: see section note)`
</vertical-slice-rules>

Give each issue its **blocking edges** - the other issues that must complete before it can start. An issue with no blockers can start immediately. `(review-time: see section note)`

**Wide refactors are the exception to vertical slicing.** A wide refactor is one mechanical change - rename a column, retype a shared symbol - whose blast radius fans across the whole codebase, so a single edit breaks many call sites at once and no vertical slice can land green. Don't force it into a tracer bullet; sequence it as expand-migrate-contract. First **expand**: add the new form beside the old so nothing breaks. Then **migrate** the call sites in batches sized by blast radius (per package, per directory), each batch its own issue blocked by the expand, keeping CI green batch to batch because the old form still exists. Finally **contract**: delete the old form once no caller remains, in an issue blocked by every migrate batch. When even the batches can't stay green alone, keep the sequence but let them share an integration branch that all block a final integrate-and-verify issue - green is promised only there. `(review-time: see section note)`

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name `(review-time: see section note)`
- **Type**: HITL / AFK `(review-time: see section note)`
- **Blocked by**: which other slices (if any) must complete first `(review-time: see section note)`
- **User stories covered**: which user stories this addresses (if the source material has them) `(review-time: see section note)`

Ask the user:

- Does the granularity feel right? (too coarse / too fine) `(review-time: see section note)`
- Are the dependency relationships correct? `(review-time: see section note)`
- Should any slices be merged or split further? `(review-time: see section note)`
- Are the correct slices marked as HITL and AFK? `(review-time: see section note)`

Iterate until the user approves the breakdown.

### 5. Publish the issues to the issue tracker

For each approved slice, publish a new issue to the issue tracker. Use the issue body template below. These issues are considered ready for AFK agents, so publish them with the correct triage label unless instructed otherwise.

Publish issues in dependency order (blockers first) so you can reference real issue identifiers in the "Blocked by" field.

Work the **frontier**: any issue whose blockers are all done - for a purely linear chain that means top to bottom. Implementation happens one issue at a time via `/build`, clearing context between issues. `(review-time: see section note)`

<issue-template>
## Parent

A reference to the parent issue on the issue tracker (if the source was an existing issue, otherwise omit this section).

## What to build

A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer implementation.

Avoid specific file paths or code snippets - they go stale fast. Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it here and note briefly that it came from a prototype. Trim to the decision-rich parts - not a working demo, just the important bits.

## Acceptance criteria

- [ ] Criterion 1 `(review-time: see section note)`
- [ ] Criterion 2 `(review-time: see section note)`
- [ ] Criterion 3 `(review-time: see section note)`

## Blocked by

- A reference to the blocking ticket (if any) `(review-time: see section note)`

Or "None - can start immediately" if no blockers.

</issue-template>

Do NOT close or modify any parent issue.
