#!/usr/bin/env bash
# Monitor GitHub CI status for the current branch.
# Uses `gh pr checks` to aggregate ALL checks for the PR.
# Falls back to `gh run list` (all runs, not just one) when no PR exists.
# Emits a line to stdout ONLY when status changes.
# Exits when the pipeline reaches a terminal state.
set -uo pipefail
# Note: no -e - gh pr checks uses non-standard exit codes (8 = pending)
# that would terminate the script under errexit

branch=$(git branch --show-current)
pr_number=$(gh pr view --json number --jq '.number' 2>/dev/null) || pr_number=""
prev=""
error_count=0

while true; do
  if [ -n "$pr_number" ]; then
    gh pr checks "$pr_number" >/dev/null 2>&1
    ec=$?
    case $ec in
      0) cur="completed|success" ;;
      1) cur="completed|failure" ;;
      8) cur="in_progress|null" ;;
      *) cur="error|exit-$ec" ;;
    esac
  else
    # Any pending run outranks a failure, so the monitor waits for every run.
    cur=$(gh run list --branch "$branch" --json status,conclusion --jq '
      if length == 0 then empty
      elif any(.[]; .status != "completed") then "in_progress|null"
      elif any(.[]; .conclusion != "success" and .conclusion != "skipped") then "completed|failure"
      else "completed|success" end' 2>/dev/null) || cur=""

    if [ -z "$cur" ]; then
      echo "no-runs|$branch"
      exit 0
    fi

    # A PR may appear after the push.
    pr_number=$(gh pr view --json number --jq '.number' 2>/dev/null) || pr_number=""
  fi

  if [[ "$cur" == error* ]]; then
    error_count=$((error_count + 1))
    if [ "$error_count" -ge 5 ]; then
      echo "error|persistent-failure"
      exit 1
    fi
  else
    error_count=0
  fi

  if [ "$cur" != "$prev" ]; then
    echo "$cur"
    prev="$cur"
    if [[ "$cur" == completed\|* ]]; then
      exit 0
    fi
  fi

  sleep 30
done
