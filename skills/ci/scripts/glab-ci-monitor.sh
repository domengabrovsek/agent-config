#!/usr/bin/env bash
# Monitor GitLab CI status for the current branch.
# Emits a line to stdout ONLY when status changes.
# Exits when the pipeline reaches a terminal state.
set -euo pipefail

prev_state=""
prev_first=""
error_count=0

while true; do
  raw=$(glab ci status 2>/dev/null) || raw=""

  if [ -z "$raw" ]; then
    error_count=$((error_count + 1))
    if [ "$error_count" -ge 5 ]; then
      echo "error|persistent-failure"
      exit 1
    fi
    sleep 30
    continue
  fi
  error_count=0

  # The trailing "Pipeline state:" line is the truth; the first job line can be a manual or skipped outlier.
  state_line=$(awk '/^Pipeline state:/ { line = $0 } END { print line }' <<<"$raw")
  state="${state_line##*: }"
  first="${raw%%$'\n'*}"

  if [ "$first" != "$prev_first" ]; then
    echo "$first"
    prev_first="$first"
  fi

  if [ "$state" != "$prev_state" ] && [ -n "$state" ]; then
    case "$state" in
      success|failed|canceled|skipped|manual)
        # Nothing more runs automatically; manual means paused on a human gate.
        echo "completed|$state"
        exit 0
        ;;
    esac
    prev_state="$state"
  fi

  sleep 30
done
