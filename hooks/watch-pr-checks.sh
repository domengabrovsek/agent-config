#!/bin/bash
# Watch PR CI checks in the background and send a macOS notification when done.
# Usage: watch-pr-checks.sh [pr-number-or-url]
# If no argument, detects the PR for the current branch.

PR_REF="${1:-}"
DEADLINE_SECONDS="${PR_CHECK_DEADLINE_SECONDS:-1800}"

# If no PR ref given, try to get it from the current branch
if [ -z "$PR_REF" ]; then
  PR_REF=$(gh pr view --json number -q '.number' 2>/dev/null)
fi

if [ -z "$PR_REF" ]; then
  exit 0
fi

PR_TITLE=$(gh pr view "$PR_REF" --json title -q '.title' 2>/dev/null || echo "PR #$PR_REF")

notify() {
  osascript -e "display notification \"$1\" with title \"$2\" sound name \"$3\""
}

# `gh pr checks --watch` blocks until every check settles, then exits 0 when
# they all passed and nonzero when any failed. Polling the table instead loses
# the failure case: gh also exits nonzero while checks are still pending.
gh pr checks "$PR_REF" --watch --fail-fast --interval 30 >/dev/null 2>&1 &
WATCH_PID=$!

# Stock macOS ships no `timeout`, so bound the wait by polling the child.
ELAPSED=0
while kill -0 "$WATCH_PID" 2>/dev/null; do
  if [ "$ELAPSED" -ge "$DEADLINE_SECONDS" ]; then
    kill "$WATCH_PID" 2>/dev/null
    wait "$WATCH_PID" 2>/dev/null
    notify "Timed out waiting for checks on: $PR_TITLE" "PR Checks Timeout" "default"
    exit 0
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

wait "$WATCH_PID"
STATUS=$?

if [ "$STATUS" -eq 0 ]; then
  notify "All checks passed on: $PR_TITLE" "PR Checks Passed" "Glass"
else
  notify "Checks failed on: $PR_TITLE" "PR Checks Failed" "Basso"
fi

exit 0
