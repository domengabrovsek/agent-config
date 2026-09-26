---
name: test
description: "Writes tests using a TDD workflow. Use when the user says 'write tests', 'add tests', 'TDD', or 'prove-it pattern'."
---

Write tests for: $ARGUMENTS

## Choose the Workflow

### For New Features: RED-GREEN-REFACTOR

**why-no-hook:** skill workflow guidance; each step requires understanding the surrounding context (repo, task shape, prior state).

1. **RED**: write a failing test that describes the expected behavior `(review-time: see section note)`
   - Test name reads like a specification: "returns empty array when no users match" `(review-time: see section note)`
   - Run the test - confirm it fails for the right reason (not a syntax error) `(review-time: see section note)`
2. **GREEN**: write the minimum code to make the test pass `(review-time: see section note)`
   - Do not optimize, do not handle edge cases yet - just make it green `(review-time: see section note)`
3. **REFACTOR**: improve the code while keeping tests green `(review-time: see section note)`
   - Extract duplication, improve naming, simplify logic `(review-time: see section note)`
   - Run tests after each refactor step `(review-time: see section note)`
4. **Repeat**: add the next test for the next behavior. Continue the cycle. `(review-time: see section note)`

### For Bug Fixes: PROVE-IT Pattern

1. **Reproduce**: write a test that triggers the exact bug as reported `(review-time: see section note)`
2. **Confirm RED**: run the test - it must fail, proving the bug exists in code `(review-time: see section note)`
3. **Fix**: implement the minimum change to fix the root cause `(review-time: see section note)`
4. **Confirm GREEN**: run the test - it must now pass `(review-time: see section note)`
5. **Regression**: run `npm run verify:fast` when package.json declares it, otherwise the full test suite. The full suite runs once per PR in `npm run verify` `(review-time: see section note)`

If you cannot write a failing test, you do not fully understand the bug. Investigate further.

## Seams - where tests go

A **seam** is the public boundary you test at: the interface where you observe behaviour without reaching inside. Tests live at seams, never against internals.

**Test only at pre-agreed seams.** Use the seams in the spec's Seams section. With no spec, write down the seams under test and confirm them with the user - no test is written at an unconfirmed seam. `(review-time: seam agreement is a conversational step, not pattern-checkable)` You can't test everything; agreeing the seams up front lands testing effort on the critical paths and complex logic instead of every edge case.

## Test Level Selection

Pick the lowest level that captures the behavior (see `~/.agents/references/testing-patterns.md`):

| Behavior | Test Level | Why |
| --- | --- | --- |
| Pure logic, calculations, validation | Unit test | Fast, isolated, deterministic |
| API request/response contracts | Integration test | Verifies real boundaries |
| Database queries, migrations | Integration test | Needs real database behavior |
| Critical user journeys | E2E test | Tests the full stack |
| Visual appearance, layout | Visual regression | Screenshot comparison |

## Anti-patterns

- **Implementation-coupled** - mocks internal collaborators, tests private methods, or verifies through a side channel (querying the database instead of using the interface). The tell: the test breaks when you refactor but behaviour hasn't changed. `(review-time: coupling detection requires reading the assertions against the implementation)`
- **Tautological** - the assertion recomputes the expected value the way the code does (`expect(add(a, b)).toBe(a + b)`, a self-derived snapshot, a constant asserted equal to itself), so it passes by construction and can never disagree with the code. Expected values must come from an independent source of truth - a known-good literal, a worked example, the spec. `(review-time: requires comparing the assertion to how the code computes)`
- **Horizontal slicing** - writing all tests first, then all implementation. Bulk tests verify _imagined_ behaviour and go insensitive to real changes. Work in vertical slices instead: one test, one implementation, repeat - each test a tracer bullet responding to what the last cycle taught you. `(review-time: workflow-shape judgment)`

## Test Quality Gates

Before considering tests complete:

- [ ] Happy path covered `(review-time: see section note)`
- [ ] Edge cases covered (empty input, boundary values, null/undefined) `(review-time: see section note)`
- [ ] Error paths covered (invalid input, network failure, timeout) `(review-time: see section note)`
- [ ] Each test is independent - passes with `test.only()` `(review-time: see section note)`
- [ ] No hardcoded test data - using factories or builders `(review-time: see section note)`
- [ ] Mocks only at module boundaries - not on internal code `(review-time: see section note)`
- [ ] Test names read like specifications `(review-time: see section note)`
- [ ] All tests pass, no flaky behavior `(review-time: see section note)`
- [ ] Regression run done: `npm run verify:fast` when declared, otherwise the full test suite `(review-time: see section note)`
