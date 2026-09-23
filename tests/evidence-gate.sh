#!/bin/bash
# Tests for hooks/pre-pr-evidence-gate.sh against a throwaway git repo with a
# spec, a ledger, and a worktree.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
GATE="$PROJECT_DIR/hooks/pre-pr-evidence-gate.sh"
# Assembled so this file never carries the literal command the hooks match.
GH_CREATE="gh ""pr create --title t --body b"
PASSED=0
FAILED=0

TMP_ROOT=$(cd "${TMPDIR:-/tmp}" && pwd)
TEST_DIR=$(cd "$(mktemp -d "$TMP_ROOT/evidence-gate-test.XXXXXX")" && pwd)

cleanup() {
  case "$TEST_DIR" in
    "$TMP_ROOT"/evidence-gate-test.*) rm -rf "$TEST_DIR" ;;
    *) echo "Refusing to clean unexpected test path: $TEST_DIR" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

pass() { PASSED=$((PASSED + 1)); echo "ok - $1"; }
fail() { FAILED=$((FAILED + 1)); echo "not ok - $1" >&2; }

REPO="$TEST_DIR/repo"
git init -q -b main "$REPO"
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "chore: init"
git -C "$REPO" checkout -q -b feat/x
HEAD_SHA=$(git -C "$REPO" rev-parse HEAD)
STATE="$REPO/.claude/state"
mkdir -p "$STATE/specs" "$STATE/runs/feat-x"

cat > "$STATE/specs/2026-09-23-spec-x.md" <<'SPEC'
---
branch: feat/x
---
# Spec: x

## Acceptance Criteria
- [ ] AC-1: parses dates | verify: test src/date.test.ts::parses
- [ ] AC-2: rejects empty input | verify: cmd npm test -- empty
- [ ] AC-3: looks right on mobile | verify: manual open the page at 375px
SPEC

ledger() {
  {
    echo "spec: .claude/state/specs/2026-09-23-spec-x.md"
    echo
    echo "| AC | status | check | evidence | sha |"
    echo "| --- | --- | --- | --- | --- |"
    printf '%s\n' "$@"
  } > "$STATE/runs/feat-x/evidence.md"
}

# assert_gate <name> <cwd> <expected-exit>
assert_gate() {
  local name="$1" cwd="$2" want="$3" got
  COMMAND="$GH_CREATE" CWD="$cwd" python3 -c 'import json,os; print(json.dumps({"tool_input":{"command":os.environ["COMMAND"]},"cwd":os.environ["CWD"]}))' \
    | bash "$GATE" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then pass "$name"; else
    echo "    want exit $want, got $got" >&2
    fail "$name"
  fi
}

PASS1="| AC-1 | PASS | test src/date.test.ts::parses | 1 passed | ${HEAD_SHA:0:7} |"
PASS2="| AC-2 | PASS | cmd npm test -- empty | 3 passed | $HEAD_SHA |"

assert_gate "a missing ledger blocks" "$REPO" 2

ledger "$PASS1"
assert_gate "a criterion with no row blocks" "$REPO" 2

ledger "$PASS1" "| AC-2 | FAIL | cmd npm test -- empty | 1 failed | ${HEAD_SHA:0:7} |"
assert_gate "a FAIL row blocks" "$REPO" 2

ledger "$PASS1" "| AC-2 | PASS | cmd npm test -- empty | 3 passed | 0000000 |"
assert_gate "a row verified at an older commit blocks" "$REPO" 2

ledger "$PASS1" "$PASS2"
assert_gate "all automated criteria passing at HEAD pass" "$REPO" 0

git -C "$REPO" checkout -q main
git -C "$REPO" worktree add -q "$TEST_DIR/wt" feat/x
assert_gate "a worktree finds the spec and ledger in the main checkout" "$TEST_DIR/wt" 0

git -C "$TEST_DIR/wt" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "fix: later"
assert_gate "a new commit makes the evidence stale" "$TEST_DIR/wt" 2

git -C "$REPO" checkout -q -b feat/no-spec
assert_gate "a branch with no spec passes" "$REPO" 0

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
