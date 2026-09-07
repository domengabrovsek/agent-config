---
name: ci
description: "Monitor the CI pipeline for the current branch via a background Monitor script (GitHub or GitLab), reacting to pass, fail, and manual-gate states. Use when the user says 'watch CI', 'monitor the pipeline', 'is CI green', or after pushing a branch or creating a PR/MR."
---

# Monitor CI Pipeline

## Workflow

**why-no-hook:** skill workflow guidance; each step requires understanding the surrounding context (repo, task shape, prior state).

1. **Detect VCS platform**: `.gitlab-ci.yml` -> glab, `.github/` -> gh `(review-time: see section note)`
2. **Start a Monitor** with the matching script: `(review-time: see section note)`
   - GitHub: `bash scripts/gh-ci-monitor.sh`, resolved inside this skill's own directory `(review-time: see section note)`
   - GitLab: `bash scripts/glab-ci-monitor.sh`, resolved inside this skill's own directory `(review-time: see section note)`
   - Use `persistent: false`, `timeout_ms: 3600000` (1 hour ceiling - CI pipelines can be long) `(review-time: see section note)`
   - Description: "CI pipeline on <branch-name>" `(review-time: see section note)`
3. **React to Monitor notifications**: `(review-time: see section note)`
   - `no-runs|<branch>`: no CI runs found for this branch - inform the user and stop `(review-time: see section note)`
   - `error|persistent-failure`: the monitor script hit 5 consecutive errors - report and stop `(review-time: see section note)`
   - Status change (e.g., `in_progress|null` → `completed|success`): acknowledge briefly `(review-time: see section note)`
   - **Pipeline passes** (`completed|success`): `(review-time: see section note)`
     - Run `~/.agents/scripts/notify.sh "CI passed - <branch-name>"` `(review-time: see section note)`
     - Report success `(review-time: see section note)`
   - **Pipeline awaiting manual action** (`completed|manual`, GitLab only): `(review-time: see section note)`
     - All automatic jobs completed; the pipeline is paused on a manual gate and will not progress without user action `(review-time: see section note)`
     - Run `~/.agents/scripts/notify.sh "CI awaiting manual action - <branch-name>"` `(review-time: see section note)`
     - Report status and stop watching - do NOT trigger the manual job automatically `(review-time: see section note)`
   - **Pipeline fails** (`completed|failure` or any non-success conclusion): `(review-time: see section note)`
     a. Fetch the job log:
        - GitLab: `glab ci trace <job-id>` `(review-time: see section note)`
        - GitHub: `gh run view <run-id> --log-failed` `(review-time: see section note)`
     b. Do NOT pipe output through head, tail, grep, or any other command - run the commands directly
     c. Analyze the root cause - identify the specific failure (test, lint, type check, build, coverage, etc.)
     d. **Classify the failure as transient or real before proposing any change** - transient = infra outage, rate limit, queued/timed-out runner, auth/network flake, registry or dependency propagation delay; real = a test/lint/type/build/coverage failure caused by the code under change. State the classification `(review-time: see section note)`
     e. **If transient**: re-run the failed job (`gh run rerun <run-id> --failed` / `glab ci retry <job-id>`) and keep monitoring - do NOT edit code for a transient failure. Escalate to the user only if it recurs after a re-run `(review-time: see section note)`
     f. Run `~/.agents/scripts/notify.sh "CI failed - <failure-summary>"`
     g. **If real, propose the fix to the user** - explain what failed and what you'd change. Do NOT push automatically `(review-time: see section note)`
     h. Wait for user approval before implementing the fix `(review-time: see section note)`
     i. After approval: fix, commit with a descriptive message, push `(review-time: see section note)`

## How it works

The monitor scripts poll CI status every 30 seconds but only emit a line when the status **changes**. This means:

- Zero token cost while the pipeline is running and status hasn't changed `(review-time: see section note)`
- Claude reacts within ~30s of a status change (vs up to 2 min with /loop) `(review-time: see section note)`
- No CronDelete cleanup needed - the script exits on terminal state, ending the Monitor `(review-time: see section note)`
- If `gh`/`glab` fails 5 times in a row (auth expired, network down), the script exits with an error notification `(review-time: see section note)`

## Important: Non-interactive commands only

These commands require a TTY and will NOT work - never use them:

- `glab ci view` (interactive TUI) `(review-time: see section note)`
- `gh run watch` (interactive watcher) `(review-time: see section note)`
- Any command with `--web` flag (opens browser) `(review-time: see section note)`

Safe commands to use:

- `glab ci status`, `glab ci list`, `glab ci trace <job-id>` `(review-time: see section note)`
- `gh pr checks`, `gh run list`, `gh run view <run-id> --log-failed` `(review-time: see section note)`

## Guardrails

- After 3 consecutive failures on the **same issue**, stop and escalate - something structural is wrong `(review-time: see section note)`
- Never weaken tests, skip linting, or lower coverage thresholds to make CI pass `(review-time: see section note)`
- Never use `--no-verify` or skip hooks `(review-time: see section note)`
- If a failure looks unrelated to your changes (flaky test, infra issue), flag it to the user rather than trying to fix it `(review-time: see section note)`
