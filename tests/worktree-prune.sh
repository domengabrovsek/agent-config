#!/bin/bash
# Tests for scripts/worktree-prune.sh verdicts and --apply removal.
#
# The load-bearing case is a squash merge: the branch tip is not an ancestor
# of the default branch, so the ancestor test misses it and upstream_gone stays
# silent while the remote branch survives. The merge-tree check must catch it.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$PROJECT_DIR/scripts/worktree-prune.sh"

TMP_ROOT=$(cd "${TMPDIR:-/tmp}" && pwd)
TEST_ROOT=$(cd "$(mktemp -d "$TMP_ROOT/worktree-prune-test.XXXXXX")" && pwd)
PASSED=0
FAILED=0

cleanup() {
  case "$TEST_ROOT" in
    "$TMP_ROOT"/worktree-prune-test.*) rm -rf "$TEST_ROOT" ;;
    *) echo "Refusing to clean unexpected test path: $TEST_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

pass() { PASSED=$((PASSED + 1)); echo "ok - $1"; }
fail() { FAILED=$((FAILED + 1)); echo "not ok - $1" >&2; }

assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qE "$needle"; then pass "$name"; else
    echo "    want match: $needle" >&2
    echo "    got: $haystack" >&2
    fail "$name"
  fi
}

REPO="$TEST_ROOT/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name Test
printf 'seed\n' > "$REPO/file"
git -C "$REPO" add file
git -C "$REPO" commit -q -m "chore: seed"

# Squash-merged branch: land its change on main as one commit, leaving the
# branch tip outside main's history.
git -C "$REPO" worktree add -q -b feature/squash "$TEST_ROOT/wt-squash"
printf 'seed\nsquash\n' > "$TEST_ROOT/wt-squash/file"
git -C "$TEST_ROOT/wt-squash" commit -q -am "feat: squash work"
git -C "$REPO" merge -q --squash feature/squash >/dev/null
git -C "$REPO" commit -q -m "feat: squash work (#1)"

# Ancestor-merged branch: fast-forward main to the tip.
git -C "$REPO" worktree add -q -b feature/ancestor "$TEST_ROOT/wt-ancestor"
printf 'seed\nancestor\n' > "$TEST_ROOT/wt-ancestor/other"
git -C "$TEST_ROOT/wt-ancestor" add other
git -C "$TEST_ROOT/wt-ancestor" commit -q -m "feat: ancestor work"
git -C "$REPO" merge -q --ff-only feature/ancestor

# Unmerged branch: unique commit that main does not have.
git -C "$REPO" worktree add -q -b feature/wip "$TEST_ROOT/wt-wip"
printf 'seed\nwip\n' > "$TEST_ROOT/wt-wip/wip"
git -C "$TEST_ROOT/wt-wip" add wip
git -C "$TEST_ROOT/wt-wip" commit -q -m "feat: unfinished work"

echo "== dry-run verdicts =="
OUT=$("$SCRIPT" --repo "$REPO" 2>&1)
assert_contains "squash merge is safe" \
  "branch=feature/squash.*reason=squash-merged-into-main" "$OUT"
assert_contains "ancestor merge is safe" \
  "branch=feature/ancestor.*reason=merged-into-main" "$OUT"
assert_contains "unmerged branch is kept" \
  "branch=feature/wip.*reason=unmerged-or-active" "$OUT"

if [ -d "$TEST_ROOT/wt-squash" ] && [ -d "$TEST_ROOT/wt-ancestor" ] && [ -d "$TEST_ROOT/wt-wip" ]; then
  pass "dry-run removes nothing"
else
  fail "dry-run removes nothing"
fi

echo
echo "== apply =="
"$SCRIPT" --repo "$REPO" --apply >/dev/null 2>&1

if [ ! -d "$TEST_ROOT/wt-squash" ] && [ ! -d "$TEST_ROOT/wt-ancestor" ]; then
  pass "apply removes the merged worktrees"
else
  fail "apply removes the merged worktrees"
fi
if [ -d "$TEST_ROOT/wt-wip" ]; then
  pass "apply keeps the unmerged worktree"
else
  fail "apply keeps the unmerged worktree"
fi
if [ -z "$(git -C "$REPO" branch --list feature/squash feature/ancestor)" ]; then
  pass "apply deletes the merged local branches"
else
  fail "apply deletes the merged local branches"
fi
if [ -n "$(git -C "$REPO" branch --list feature/wip)" ]; then
  pass "apply keeps the unmerged local branch"
else
  fail "apply keeps the unmerged local branch"
fi

echo ""
echo "$PASSED passed; $FAILED failed"
[ "$FAILED" -eq 0 ]
