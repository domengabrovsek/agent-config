#!/bin/bash
# Tests for hooks/pre-edit-test-lock.sh against a throwaway git repo with a
# branch lock and a worktree.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
GATE="$PROJECT_DIR/hooks/pre-edit-test-lock.sh"
PASSED=0
FAILED=0

TMP_ROOT=$(cd "${TMPDIR:-/tmp}" && pwd)
TEST_DIR=$(cd "$(mktemp -d "$TMP_ROOT/test-lock-test.XXXXXX")" && pwd)

cleanup() {
  case "$TEST_DIR" in
    "$TMP_ROOT"/test-lock-test.*) rm -rf "$TEST_DIR" ;;
    *) echo "Refusing to clean unexpected test path: $TEST_DIR" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

pass() { PASSED=$((PASSED + 1)); echo "ok - $1"; }
fail() { FAILED=$((FAILED + 1)); echo "not ok - $1" >&2; }

REPO="$TEST_DIR/repo"
git init -q -b main "$REPO"
mkdir -p "$REPO/src"
echo "test" > "$REPO/src/date.test.ts"
echo "code" > "$REPO/src/date.ts"
git -C "$REPO" add -A
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m "test: add date tests"
git -C "$REPO" branch -q feat/x
mkdir -p "$REPO/.claude/state/runs/feat-x"
echo "src/date.test.ts" > "$REPO/.claude/state/runs/feat-x/tests.lock"
git -C "$REPO" worktree add -q "$TEST_DIR/wt" feat/x

# assert_gate <name> <file> <agent_type or empty> <expected-exit>
assert_gate() {
  local name="$1" file="$2" agent="$3" want="$4" got
  FILE="$file" AGENT="$agent" python3 -c '
import json, os
p = {"tool_input": {"file_path": os.environ["FILE"]}}
if os.environ["AGENT"]:
    p["agent_type"] = os.environ["AGENT"]
print(json.dumps(p))' | bash "$GATE" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then pass "$name"; else
    echo "    want exit $want, got $got" >&2
    fail "$name"
  fi
}

WT_TEST="$TEST_DIR/wt/src/date.test.ts"
assert_gate "an implementer editing a locked test is blocked" "$WT_TEST" "Backend Staff Engineer" 2
assert_gate "the main session editing a locked test is blocked" "$WT_TEST" "" 2
assert_gate "the QA Expert may edit a locked test" "$WT_TEST" "QA Expert" 0
assert_gate "an implementer may edit source code" "$TEST_DIR/wt/src/date.ts" "Backend Staff Engineer" 0
assert_gate "a new untracked file is not locked" "$TEST_DIR/wt/src/new.test.ts" "Backend Staff Engineer" 0
assert_gate "a branch with no lock is not gated" "$REPO/src/date.test.ts" "Backend Staff Engineer" 0

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
