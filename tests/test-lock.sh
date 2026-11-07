#!/bin/bash
# Tests for hooks/pre-edit-test-lock.sh against a throwaway git repo with a
# branch lock and a worktree.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
GATE="$PROJECT_DIR/hooks/pre-edit-test-lock.sh"

harness_init test-lock TEST_DIR

REPO="$TEST_DIR/repo"
mkdir -p "$REPO/src"
echo "test" > "$REPO/src/date.test.ts"
echo "code" > "$REPO/src/date.ts"
make_repo "$REPO"
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

mkdir -p "$TEST_DIR/wt/.claude/state/runs/feat-x"
: > "$TEST_DIR/wt/.claude/state/runs/feat-x/tests.lock"
assert_gate "a worktree's empty lock does not shadow the main checkout's" "$WT_TEST" "Backend Staff Engineer" 2

git -C "$REPO" worktree add -q -b feat/y "$TEST_DIR/wt-y" main
mkdir -p "$TEST_DIR/wt-y/.claude/state/runs/feat-y"
echo "src/date.test.ts" > "$TEST_DIR/wt-y/.claude/state/runs/feat-y/tests.lock"
assert_gate "a worktree's lock applies when the main checkout has none" \
  "$TEST_DIR/wt-y/src/date.test.ts" "Backend Staff Engineer" 2

BARE_HOME="$TEST_DIR/bare-home"
mkdir -p "$BARE_HOME"
git clone -q --bare "$REPO" "$BARE_HOME/repo.git"
git -C "$BARE_HOME/repo.git" worktree add -q -b feat/z "$BARE_HOME/wt-z" main
mkdir -p "$BARE_HOME/wt-z/.claude/state/runs/feat-z" "$BARE_HOME/.claude/state/runs/feat-z"
echo "src/date.test.ts" > "$BARE_HOME/wt-z/.claude/state/runs/feat-z/tests.lock"
: > "$BARE_HOME/.claude/state/runs/feat-z/tests.lock"
assert_gate "a bare repo's parent folder is not read as a main checkout" \
  "$BARE_HOME/wt-z/src/date.test.ts" "Backend Staff Engineer" 2

finish
