---
name: debug
description: "Runs a structured production-incident investigation that forces evidence-first hypothesis ranking before any code change. Use when given an error message, Sentry alert, failing log, or an 'investigate <X>' request."
---

Investigate the issue: $ARGUMENTS

Hard rule: do NOT write any fix until Phase 3 is reached and the user (or the evidence in Phase 2) has confirmed the root cause.

## Phase 1 - Evidence

**why-no-hook:** skill workflow guidance; each step requires understanding the surrounding context (repo, task shape, prior state).

Gather, do not theorize. Save findings to `.claude/state/research/YYYY-MM-DD-debug-<short-slug>.md`.

- If given a Sentry issue (short ID like `PROJECT-ABC`, numeric ID, or sentry.io URL), fetch the digest first via the `sentry-issue` skill: `~/.agents/skills/sentry-issue/scripts/sentry-issue.sh <id>`. Full payloads land in `/tmp/sentry-{issue,event}-<id>.json` for deeper `jq` queries. `(review-time: see section note)`
- Reproduce locally if feasible. Capture exact error, stack trace, request ID, timestamp. `(review-time: see section note)`
- Pull logs (Sentry, Cloud Run, container, browser console) for the affected window. `(review-time: see section note)`
- `git log -p --since='2 weeks ago' -- <suspect-paths>` to surface recent changes that touched the code path. `(review-time: see section note)`
- Confirm scope: how many users / requests / environments are affected. `(review-time: see section note)`
- Check related state: env vars set on the deployed service, DB row state, feature flags, recent deploys. `(review-time: see section note)`

If the user already supplied a hypothesis, treat it as a candidate but still gather evidence to confirm or reject.

### Build a red-capable feedback loop

Before hypothesising, build a **tight, red-capable feedback loop** - one command (a failing test, a curl against a running server, a CLI invocation diffing output, a replayed trace) that you have **already run at least once** and that goes red on _this_ bug and green once fixed. Tighten it: faster, sharper signal, more deterministic (pin time, seed RNG). For a flaky bug, raise the reproduction rate until it's debuggable rather than chasing a clean repro. Then **minimise** - shrink to the smallest scenario that still goes red, cutting inputs, config, and steps one at a time. `(review-time: loop construction is creative work, not pattern-checkable)`

No red-capable command, no Phase 2 - jumping to a hypothesis before the loop exists is the exact failure this skill prevents. If you genuinely cannot build one (production-only, no local repro), say so explicitly, list what you tried, and ask the user for environment access or a captured artifact (HAR, log dump, core dump) before proceeding. `(review-time: gate is a judgment about whether a real red-capable loop exists)`

## Phase 2 - Hypotheses

List 3-5 possible root causes ranked by evidence strength - generating several up front stops you anchoring on the first plausible idea. For each:

- **Hypothesis** - one line. `(review-time: see section note)`
- **Prediction** - the falsifiable test it implies: "if this is the cause, then changing X makes the bug disappear / changing Y makes it worse." If you can't state a prediction, it's a vibe - sharpen or discard it. `(review-time: falsifiability judgment, not pattern-checkable)`
- **Evidence for** - log lines, commits, or code paths that support it (with file:line refs). `(review-time: see section note)`
- **Evidence against** - what would have to be true that isn't. `(review-time: see section note)`
- **Cheapest verification** - what one command, query, or read would confirm or rule it out. `(review-time: see section note)`

Pick the top candidate. If two are tied or the user has a strong prior, ask the user to choose. Do not proceed to Phase 3 on a guess.

## Phase 3 - Fix

- Minimal change first per CLAUDE.md (1-5 lines, ideally). State the change before applying it. `(review-time: see section note)`
- Add a regression test that reproduces the original failure and now passes - only at a correct seam that exercises the real bug pattern; if no such seam exists, that itself is the finding, note it and hand off to `/improve-codebase-architecture`. `(review-time: see section note)`
- Remove all temporary instrumentation before committing - tag every debug log with a unique prefix like `[DEBUG-a4f2]` when you add it, so cleanup is a single grep. `(review-time: see section note)`
- Run `/verify-done` (lint + typecheck + test + build). `(review-time: see section note)`
- Commit on a feature branch with a conventional message that names the root cause. `(review-time: see section note)`
- Open a PR per `mr` skill. PR body: link to the alert/log, root cause statement with evidence, and why this fix is correct. `(review-time: see section note)`

## Anti-patterns - reject these

- Adding retry / fallback / try-catch as a "fix" before root cause is confirmed. `(review-time: see section note)`
- Introducing new abstractions, services, or workspaces as part of a debug fix. `(review-time: see section note)`
- Editing logs to make the symptom disappear. `(review-time: see section note)`
- Leaving untagged debug instrumentation in the code after the fix. `(review-time: see section note)`
- Expanding scope ("while I'm here, let me also..."). `(review-time: see section note)`
- Pushing before all checks pass green locally. `(review-time: see section note)`
