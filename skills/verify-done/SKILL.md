---
name: verify-done
description: "Runs the comprehensive quality gate before declaring work done: the repo's `npm run verify` when package.json declares it, otherwise the checks CI runs, then reviews git status and the session diff. Use when the user says 'verify done' or '/verify-done', or before pushing any branch."
---

Comprehensive quality gate before declaring work done.

**When package.json declares a `verify` script**, the repo owns the gate. Skip steps 1 and 2:

- Run `npm run verify` once, with `run_in_background` or a 600000ms timeout. It takes minutes.
- Do not read workflow YAML or run individual checks. `verify` mirrors CI and prints what it skips.
- On success with a clean tree, `verify` writes HEAD to `<git-dir>/verify-passed`. The PR-open hook reads that stamp.
- Continue at step 3.

**Otherwise:**

1. **Discover CI steps**: read `.github/workflows/*.yml` (or `.gitlab-ci.yml`, `Jenkinsfile`, etc.) and `package.json` scripts to find the actual checks CI runs. Only run what CI actually runs - do not guess or add extra steps.
2. **Run each CI step in order**: execute the discovered commands (lint, typecheck, test, build, etc.) in the same order as CI. Stop at the first failure.
3. **Git status**: show uncommitted changes and untracked files.
4. **Diff review**: summarize what changed in this session (files, lines added/removed).
5. **Spec check**: if a spec in `.claude/state/specs/` has `branch: <current branch>`, spawn the `Spec Verifier` and include its verdict. Any automated criterion not PASS at HEAD fails the gate.

If all CI steps pass and git status is clean: output "READY - all quality gates passed."
If any step fails: list failures and stop. Do NOT declare work done.
If no CI configuration is found, say so and ask the user what checks to run.
