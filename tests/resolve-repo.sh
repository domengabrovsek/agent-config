#!/bin/bash
# Tests for hooks/lib/resolve-repo.sh and the hooks that use it (three covered end to end below).
#
# The end-to-end cases run each hook from a cwd that is NOT the repo, with
# CLAUDE_PROJECT_DIR unset, which is how the harness actually invokes them.
# That is the shape that had pre-git-state-refresh reporting "not-a-repo" for
# every git command.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
# shellcheck source=../hooks/lib/resolve-repo.sh
. "$PROJECT_DIR/hooks/lib/resolve-repo.sh"

harness_init resolve-repo

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

assert_eq "a ~ cd path expands to HOME" \
  "$OTHER" "$(HOME="$TEST_ROOT" resolve_repo_dir "cd ~/other && git push" "$REPO" push)"

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

: > "$REPO/file"
make_repo "$REPO"
git -C "$REPO" checkout -q -b feature/branch

# Run every hook from a directory that is not a repo, with no project dir,
# exactly as the harness does. Sets OUT and STATUS.
run_hook() {
  OUT=$(payload "$2" "$REPO" | (cd "$TEST_ROOT" && CLAUDE_PROJECT_DIR="" bash "$PROJECT_DIR/hooks/$1" 2>&1))
  STATUS=$?
}
diagnose() { echo "    exit $STATUS, got: $OUT"; }

run_hook pre-git-state-refresh.sh "git push origin feature/branch"
check "pre-git-state-refresh finds the repo and branch" omits "not-a-repo" says "branch=feature/branch"

# gh reads the branch from its cwd, so this stub answers only when it runs in
# the payload repo. Run anywhere else, the probe reports the wrong PR state.
BIN="$TEST_ROOT/bin"
stub "$BIN" gh <<'STUB'
#!/bin/bash
[ "$(pwd -P)" = "$GH_STUB_DIR" ] || exit 1
echo '{"state":"MERGED","mergedAt":"2026-01-01T00:00:00Z","url":"https://example.test/pull/1"}'
STUB
git init -q --bare "$TEST_ROOT/origin.git"
git -C "$REPO" remote add origin "$TEST_ROOT/origin.git"
GH_STUB_DIR=$(cd "$REPO" && pwd -P) PATH="$BIN:$PATH" \
  run_hook pre-git-state-refresh.sh "git push origin feature/branch"
check "pre-git-state-refresh asks gh about the payload repo's branch" says "state=MERGED"

# The branch gate must see the payload repo's branch, not the caller's.
git -C "$REPO" checkout -q -B main
run_hook pre-commit-branch-gate.sh "git commit -m 'feat: x'"
check "pre-commit-branch-gate blocks main in the payload repo" \
  exited 2 says "Refusing to commit directly to 'main'"

git -C "$REPO" checkout -q -b feature/other
run_hook pre-commit-branch-gate.sh "git commit -m 'feat: x'"
check "pre-commit-branch-gate allows a feature branch" [ -z "$OUT" ]

# The push gate walks up from the resolved dir; a repo with no package.json
# and no *.tf is skipped silently, which proves it resolved somewhere real
# rather than walking up from the hook's own cwd.
run_hook pre-push-gate.sh "git push origin feature/other"
check "pre-push-gate skips a project with no manifest" [ -z "$OUT" ]

finish
