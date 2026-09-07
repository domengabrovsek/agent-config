#!/bin/bash
# Tests for hooks/lib/resolve-repo.sh and the three hooks that use it.
#
# The end-to-end cases run each hook from a cwd that is NOT the repo, with
# CLAUDE_PROJECT_DIR unset, which is how the harness actually invokes them.
# That is the shape that had pre-git-state-refresh reporting "not-a-repo" for
# every git command.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../hooks/lib/resolve-repo.sh
. "$PROJECT_DIR/hooks/lib/resolve-repo.sh"

TMP_ROOT=$(cd "${TMPDIR:-/tmp}" && pwd)
TEST_ROOT=$(cd "$(mktemp -d "$TMP_ROOT/resolve-repo-test.XXXXXX")" && pwd)
PASSED=0
FAILED=0

cleanup() {
  case "$TEST_ROOT" in
    "$TMP_ROOT"/resolve-repo-test.*) rm -rf "$TEST_ROOT" ;;
    *) echo "Refusing to clean unexpected test path: $TEST_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

pass() { PASSED=$((PASSED + 1)); echo "ok - $1"; }
fail() { FAILED=$((FAILED + 1)); echo "not ok - $1" >&2; }

assert_eq() {
  local name="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then pass "$name"; else
    echo "    want: $want" >&2
    echo "    got:  $got" >&2
    fail "$name"
  fi
}

REPO="$TEST_ROOT/repo"
OTHER="$TEST_ROOT/other"
mkdir -p "$REPO" "$OTHER"
CLAUDE_PROJECT_DIR="$TEST_ROOT/project-dir"
export CLAUDE_PROJECT_DIR

echo "== resolve_repo_dir =="
assert_eq "payload cwd wins when the command carries no path" \
  "$REPO" "$(resolve_repo_dir "git push origin main" "$REPO" push)"

assert_eq "git -C beats the payload cwd" \
  "$OTHER" "$(resolve_repo_dir "git -C $OTHER push origin main" "$REPO" push)"

assert_eq "a leading cd beats the payload cwd" \
  "$OTHER" "$(resolve_repo_dir "cd $OTHER && git push" "$REPO" push)"

assert_eq "a quoted cd path is unquoted" \
  "$OTHER" "$(resolve_repo_dir "cd \"$OTHER\" && git push" "$REPO" push)"

assert_eq "a cd terminated by a semicolon still parses" \
  "$OTHER" "$(resolve_repo_dir "cd $OTHER ; git push" "$REPO" push)"

assert_eq "a relative -C path anchors to the payload cwd" \
  "$REPO/sub" "$(resolve_repo_dir "git -C sub push" "$REPO" push)"

assert_eq "CLAUDE_PROJECT_DIR is the fallback when no cwd is supplied" \
  "$CLAUDE_PROJECT_DIR" "$(resolve_repo_dir "git push" "" push)"

assert_eq "the default subcommand matches any git verb" \
  "$OTHER" "$(resolve_repo_dir "git -C $OTHER commit -m x" "$REPO")"

echo
echo "== hooks resolve the repo from the payload, not their own cwd =="

git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name Test
: > "$REPO/file"
git -C "$REPO" add file
git -C "$REPO" commit -q -m "chore: seed"
git -C "$REPO" checkout -q -b feature/branch

# Run every hook from a directory that is not a repo, with no project dir,
# exactly as the harness does.
run_hook() {
  local hook="$1" command="$2"
  printf '{"cwd":"%s","tool_input":{"command":"%s"}}' "$REPO" "$command" \
    | (cd "$TEST_ROOT" && CLAUDE_PROJECT_DIR="" bash "$PROJECT_DIR/hooks/$hook" 2>&1)
}

OUT=$(run_hook pre-git-state-refresh.sh "git push origin feature/branch")
case "$OUT" in
  *"not-a-repo"*) fail "pre-git-state-refresh finds the repo (got not-a-repo)" ;;
  *"branch=feature/branch"*) pass "pre-git-state-refresh finds the repo and branch" ;;
  *) echo "    got: $OUT" >&2; fail "pre-git-state-refresh finds the repo and branch" ;;
esac

# The branch gate must see the payload repo's branch, not the caller's.
git -C "$REPO" checkout -q -B main
OUT=$(run_hook pre-commit-branch-gate.sh "git commit -m 'feat: x'")
STATUS=$?
if [ "$STATUS" -eq 2 ] || printf '%s' "$OUT" | grep -q "Refusing to commit directly to 'main'"; then
  pass "pre-commit-branch-gate blocks main in the payload repo"
else
  echo "    got: $OUT" >&2
  fail "pre-commit-branch-gate blocks main in the payload repo"
fi

git -C "$REPO" checkout -q -b feature/other
OUT=$(run_hook pre-commit-branch-gate.sh "git commit -m 'feat: x'")
if [ -z "$OUT" ]; then
  pass "pre-commit-branch-gate allows a feature branch"
else
  echo "    got: $OUT" >&2
  fail "pre-commit-branch-gate allows a feature branch"
fi

# The push gate walks up from the resolved dir; a repo with no package.json
# and no *.tf is skipped silently, which proves it resolved somewhere real
# rather than walking up from the hook's own cwd.
OUT=$(run_hook pre-push-gate.sh "git push origin feature/other")
if [ -z "$OUT" ]; then
  pass "pre-push-gate skips a project with no manifest"
else
  echo "    got: $OUT" >&2
  fail "pre-push-gate skips a project with no manifest"
fi

echo ""
echo "$PASSED passed; $FAILED failed"
[ "$FAILED" -eq 0 ]
