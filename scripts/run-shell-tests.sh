#!/bin/bash
# Run every tests/*.sh suite in parallel and report the failed ones.
#
# The glob picks up a new suite without a workflow edit. Each suite works in
# its own temp dir, so the suites run at once, each into its own log. The logs
# print in glob order, one block per suite, and the run fails after listing
# every failed suite. Under GitHub Actions each block is a collapsible log
# group and the failure list is an error annotation.
#
# Usage: scripts/run-shell-tests.sh [--help]
set -euo pipefail

case "${1:-}" in
  -h|--help) sed -n '2,/^[^#]/s/^# \{0,1\}//p' "$0"; exit 0 ;;
  "") ;;
  *) echo "Unknown argument: $1" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -n "${RUNNER_TEMP:-}" ]; then
  logs="$RUNNER_TEMP/shell-suites"
  mkdir -p "$logs"
else
  logs="$(mktemp -d "${TMPDIR:-/tmp}/shell-suites.XXXXXX")"
  trap 'rm -rf "$logs"' EXIT
fi

suites=(tests/*.sh)
pids=()
for t in "${suites[@]}"; do
  bash "$t" > "$logs/$(basename "$t").log" 2>&1 &
  pids+=("$!")
done

failed=""
for i in "${!suites[@]}"; do
  t=${suites[$i]}
  if wait "${pids[$i]}"; then result=passed; else result=FAILED; failed="$failed $t"; fi
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::group::$t ($result)"
    cat "$logs/$(basename "$t").log"
    echo "::endgroup::"
  else
    echo "== $t ($result)"
    cat "$logs/$(basename "$t").log"
    echo
  fi
done

if [ -n "$failed" ]; then
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error::Failed suites:$failed"
  else
    echo "Failed suites:$failed" >&2
  fi
  exit 1
fi
echo "OK: ${#suites[@]} shell suites passed."
