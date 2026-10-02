#!/bin/bash
# Tests for scripts/statusline.sh. Each run uses an empty config dir and a
# non-git cwd, so the credits block and the git block stay out of the output.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$PROJECT_DIR/scripts/statusline.sh"
TMP_ROOT=$(cd "${TMPDIR:-/tmp}" && pwd)
TEST_DIR=$(cd "$(mktemp -d "$TMP_ROOT/statusline-test.XXXXXX")" && pwd)
PASSED=0
FAILED=0

cleanup() {
  case "$TEST_DIR" in
    "$TMP_ROOT"/statusline-test.*) rm -rf "$TEST_DIR" ;;
    *) echo "Refusing to clean unexpected test path: $TEST_DIR" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

pass() { PASSED=$((PASSED + 1)); echo "ok - $1"; }
fail() { FAILED=$((FAILED + 1)); echo "not ok - $1" >&2; }

# render <json>: prints the status line with ANSI codes stripped
render() {
  printf '%s' "$1" | CLAUDE_CONFIG_DIR="$TEST_DIR" sh "$SCRIPT" | sed 's/\x1b\[[0-9;]*m//g'
}

# assert_contains <name> <haystack> <needle>
assert_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) echo "    output: $2" >&2; fail "$1" ;;
  esac
}

# assert_lacks <name> <haystack> <needle>
assert_lacks() {
  case "$2" in
    *"$3"*) echo "    output: $2" >&2; fail "$1" ;;
    *) pass "$1" ;;
  esac
}

out=$(render "{\"cwd\":\"$TEST_DIR\",\"model\":{\"display_name\":\"Opus 5.5\"},\"effort\":{\"level\":\"high\"}}")
assert_contains "shows the model and its effort" "$out" "Opus 5.5 high"

out=$(render "{\"cwd\":\"$TEST_DIR\",\"model\":{\"display_name\":\"Haiku 4.5\"}}")
assert_contains "shows the model without effort when effort is absent" "$out" "Haiku 4.5"
assert_contains "omits the effort when it is absent" "$out" "Haiku 4.5 │"

out=$(render "{\"cwd\":\"$TEST_DIR\"}")
assert_lacks "omits the model block when no model is sent" "$out" "null"

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
