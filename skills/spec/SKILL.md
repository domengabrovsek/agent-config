---
name: spec
description: "Defines requirements before planning. Use when starting a new feature, when requirements are ambiguous, or when the user says 'write a spec' or 'define requirements'."
---

Write a specification for: $ARGUMENTS

Follow this workflow:

1. **Discovery**: ask the user clarifying questions before writing anything. Cover:
   - **Who** - who is the user/audience for this feature?
   - **What** - what exactly should it do? What is the expected behavior?
   - **Why** - what problem does it solve? What is the success metric?
   - **Constraints** - what technical, time, or scope constraints exist?
   - **Boundaries** - what is explicitly out of scope?
   - Ask **one question at a time**, waiting for the answer before asking the next. The list above is the topic checklist to cover across the discovery phase, not a batch to dump in one turn. See `rules/communication.md`.

2. **Draft the spec**: based on the answers, write a specification with these sections. Give every acceptance criterion an ID and a check. Prefer `test` or `cmd`; use `manual` only when no command can prove it:

```markdown
---
branch: <feature branch, filled in when build starts>
---
# Spec: <title>

## Problem Statement
<What problem does this solve and for whom?>

## User Stories
- As a <role>, I want <capability> so that <benefit>

## Acceptance Criteria
- [ ] AC-1: <Specific, testable criterion> | verify: test <file>::<test name>
- [ ] AC-2: <Specific, testable criterion> | verify: cmd <command whose output shows it>
- [ ] AC-3: <Criterion only a person can judge> | verify: manual <steps>

## Seams
- <Where tests exercise the behaviour, chosen highest and fewest>

## Non-Functional Requirements
- Performance: <latency, throughput targets>
- Security: <auth, data handling requirements>
- Accessibility: <WCAG level, specific requirements>

## Technical Constraints
- <Stack, infrastructure, API compatibility requirements>

## Out of Scope
- <Explicitly excluded from this work, each item with the reason it is out>

## Open Questions
**why-no-hook:** skill workflow guidance; each step requires understanding the surrounding context (repo, task shape, prior state).

- <Anything unresolved that needs a decision>
```

1. **Save**: save the spec to `.claude/state/specs/YYYY-MM-DD-spec-<topic>.md` `(review-time: see section note)`
2. **Review**: present the spec to the user. Wait for approval before proceeding to /plan. `(review-time: see section note)`
3. **Iterate**: if the user has feedback, update the spec and re-present. Repeat until approved. `(review-time: see section note)`

Do NOT proceed to planning or implementation until the spec is explicitly approved.
