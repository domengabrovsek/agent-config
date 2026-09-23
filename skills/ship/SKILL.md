---
name: ship
description: "Runs pre-launch validation and the release workflow. Use when the user says 'ship', 'release', 'deploy', or 'ready to merge'."
---

Validate and ship: $ARGUMENTS

## Pre-Ship Checklist

Run these checks in order. Stop at the first failure.

### 1. Code Quality

**why-no-hook:** skill workflow guidance; each step requires understanding the surrounding context (repo, task shape, prior state).

- [ ] Run `/verify-done` - stop on first failure (typecheck + lint + tests + build) `(review-time: see section note)`
- [ ] No debugging artifacts (`console.log`, `debugger`, `.only()`, `TODO` or `FIXME` markers) `(review-time: see section note)`

### 2. Git Hygiene

- [ ] Branch is rebased onto target: `git fetch origin main && git rebase origin/main` `(review-time: see section note)`
- [ ] No uncommitted changes: `git status` is clean `(review-time: see section note)`
- [ ] Commits follow conventional format (`feat:`, `fix:`, `refactor:`, etc.) `(review-time: see section note)`
- [ ] Each commit is atomic (one logical change per commit) `(review-time: see section note)`
- [ ] No merge conflict markers in code `(review-time: see section note)`
- [ ] No sensitive files staged (`.env`, credentials, keys) `(review-time: see section note)`

### 3. Security Review (see `~/.agents/references/security-checklist.md`; spawn the `Cybersecurity Expert` teammate for risky changes)

- [ ] No secrets in code or commit history `(review-time: see section note)`
- [ ] Dependencies clean: `npm audit` with zero critical/high `(review-time: see section note)`
- [ ] Input validation at system boundaries `(review-time: see section note)`
- [ ] Auth/authorization checks on new endpoints `(review-time: see section note)`
- [ ] Security headers configured if applicable `(review-time: see section note)`

### 4. Change Review

- [ ] Summarize what changed (files, lines added/removed) `(review-time: see section note)`
- [ ] Flag risky changes: auth logic, migrations, public API changes, config changes `(review-time: see section note)`
- [ ] Verify backward compatibility for API changes `(review-time: see section note)`
- [ ] If migrations exist: verify they are reversible and backward-compatible `(review-time: see section note)`

### 5. Documentation

- [ ] README updated if public API or setup steps changed `(review-time: see section note)`
- [ ] Changelog or release notes drafted if applicable `(review-time: see section note)`

### 6. Version (if applicable)

- Determine version bump from conventional commits: `(review-time: see section note)`
  - `fix:` commits = PATCH bump `(review-time: see section note)`
  - `feat:` commits = MINOR bump `(review-time: see section note)`
  - `BREAKING CHANGE:` = MAJOR bump `(review-time: see section note)`
- Update version in package.json if needed `(review-time: see section note)`

## Ship It

If all checks pass:

1. Create the PR with `/mr`, which fills the repo template, links the issues, and creates it without a confirmation step `(review-time: see section note)`
2. Request reviewers if specified `(review-time: see section note)`
3. Report: "READY TO SHIP - all pre-launch checks passed" `(review-time: see section note)`

If any check fails:

1. List failures with specific details `(review-time: see section note)`
2. Stop - do NOT create the PR until all checks pass `(review-time: see section note)`

## Rollout and rollback (deploys)

For a staged rollout, decide per stage from thresholds, never from feel:

| Metric | Advance | Hold and investigate | Roll back |
| --- | --- | --- | --- |
| Error rate | Within 10% of baseline | 10-100% above baseline | More than 2x baseline |
| p95 latency | Within 20% of baseline | 20-50% above baseline | More than 50% above |
| Client JS errors | No new error types | New errors under 0.1% of sessions | New errors over 0.1% of sessions |
| Business metrics | Neutral or positive | Decline under 5% (may be noise) | Decline over 5% |

Write the rollback plan before the deploy, never during the incident:

```text
Trigger conditions: error rate > 2x baseline, p95 > <X>ms, or reports of <specific issue>.
Steps: disable the feature flag, or deploy the previous version. Verify via
health check and error monitoring. Notify the team.
Database: name the migration rollback command; state whether data written by
the new feature is preserved or cleaned up.
Time to rollback: flag under 1 minute, redeploy under 5, database under 15.
```
