#!/bin/bash
# Tests for hooks/lib/once.sh. Each case points the temp dir variable at its
# own dir, so the claims never mix with a real session or another suite.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
# shellcheck source=../hooks/lib/once.sh
. "$PROJECT_DIR/hooks/lib/once.sh"

harness_init once-lib TEST_DIR

PAYLOAD='{"tool_use_id": "toolu_once", "hook_event_name": "PreToolUse"}'

# claims <dir>: the results of two runs on one tool call under <dir>, such as "0 1".
claims() {
  local out="" status
  for _ in 1 2; do
    (export TMPDIR="$1"; first_run_for_call "$PAYLOAD" gate)
    status=$?
    out="$out $status"
  done
  echo "${out# }"
}

eq() {
  if [ "$1" = "$2" ]; then pass "$3"; else echo "    want $2, got $1" >&2; fail "$3"; fi
}

echo "== claim dir =="
mkdir -p "$TEST_DIR/fresh"
eq "$(claims "$TEST_DIR/fresh")" "0 1" "the first run claims the call and a later run skips"
eq "$(ls -ld "$TEST_DIR/fresh/agent-hook-once" | cut -c1-10)" "drwx------" "a new claim dir is private to the user"

# A dir owned by another user takes the same branch as a symlink, and only
# root can create one, so the symlink stands in for it here.
mkdir -p "$TEST_DIR/linked" "$TEST_DIR/elsewhere"
ln -s "$TEST_DIR/elsewhere" "$TEST_DIR/linked/agent-hook-once"
eq "$(claims "$TEST_DIR/linked")" "0 1" "a symlinked claim dir falls back and still dedupes"
eq "$(ls -A "$TEST_DIR/elsewhere")" "" "no claim lands behind the symlink"
eq "$(ls -ld "$TEST_DIR/linked/agent-hook-once-$(id -u)" | cut -c1-10)" "drwx------" "the per-user dir is private"

mkdir -p "$TEST_DIR/blocked"
printf 'x' > "$TEST_DIR/blocked/agent-hook-once"
eq "$(claims "$TEST_DIR/blocked")" "0 0" "an unusable claim dir fails open and runs every time"

eq "$(first_run_for_call '{}' gate; echo $?)" "0" "a payload without a tool_use_id runs"

finish
