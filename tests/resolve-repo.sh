#!/bin/bash
# Tests for hooks/lib/resolve-repo.sh and the hooks that use it.
#
# The end-to-end cases run each hook from a cwd that is NOT the repo, which is
# how the harness invokes them. The worktree cases set cwd, git -C, and
# CLAUDE_PROJECT_DIR to disagree, and check that the most explicit one wins.

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

SPACED="$TEST_ROOT/with space"
assert_eq "a quoted -C path is unquoted, not read relative" \
  "$SPACED" "$(resolve_repo_dir "git -C \"$SPACED\" push" "$REPO" push)"

assert_eq "a ~ -C path expands to HOME" \
  "$OTHER" "$(HOME="$TEST_ROOT" resolve_repo_dir "git -C ~/other push" "$REPO" push)"

assert_eq "the last cd before git wins" \
  "$OTHER" "$(resolve_repo_dir "cd /tmp; cd $OTHER && git push" "$REPO" push)"

assert_eq "a cd inside a subshell applies to the git call in it" \
  "$OTHER" "$(resolve_repo_dir "(cd $OTHER && git push)" "$REPO" push)"

assert_eq "a closed subshell restores the directory" \
  "$REPO" "$(resolve_repo_dir "(cd $OTHER); git push" "$REPO" push)"

assert_eq "cd - returns to the previous directory" \
  "$REPO" "$(resolve_repo_dir "cd /notrepo && cd - && git push" "$REPO" push)"

assert_eq "--work-tree names the repo" \
  "$OTHER" "$(resolve_repo_dir "git --git-dir=$OTHER/.git --work-tree=$OTHER push" "$REPO" push)"

assert_eq "--git-dir alone names the repo above it" \
  "$OTHER" "$(resolve_repo_dir "git --git-dir $OTHER/.git push" "$REPO" push)"

assert_eq "a variable set earlier in the chain expands in cd" \
  "$OTHER" "$(resolve_repo_dir "D=$OTHER; cd \"\$D\" && git push" "$REPO" push)"

assert_eq "the last matching call names the repo" \
  "$OTHER" "$(resolve_repo_dir "git -C $REPO commit -m x && git -C $OTHER push" "$REPO" push)"

assert_eq "a gh call after cd resolves to that directory" \
  "$OTHER" "$(resolve_repo_dir "git -C $REPO push && cd $OTHER && gh pr create" "$REPO")"

echo
echo "== git_runs =="
GIT_PUSH="git ""push"
for CMD in "$GIT_PUSH origin HEAD" "git -C \"$SPACED\" push" "git -c core.x=y push" \
  "git --no-pager push" "FOO=1 $GIT_PUSH" "env FOO=1 $GIT_PUSH" "cd $OTHER && $GIT_PUSH"; do
  check "'$CMD' runs push" git_runs "$CMD" push
done
for CMD in "echo \"$GIT_PUSH\"" "git commit -m \"docs: explain $GIT_PUSH\"" "git -C $OTHER status" \
  "grep -r '$GIT_PUSH' hooks" "cat <<'EOF'
$GIT_PUSH origin main
EOF"; do
  check "'$CMD' does not run push" not git_runs "$CMD" push
done
check "a list of subcommands matches either" git_runs "git -C $OTHER commit -m x" "push|commit"
parse_git_command "git -C $OTHER push -u origin HEAD" "$REPO" push
check "the matched call's arguments come back" [ "${GIT_ARGS[*]}" = "-u origin HEAD" ]

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
check "pre-git-state-refresh skips gh for a branch never pushed" says "state=NONE (branch never pushed)"

# A branch cut from origin/main tracks it, yet has never been pushed itself.
git -C "$REPO" push -q origin main
git -C "$REPO" fetch -q origin
git -C "$REPO" branch -q --set-upstream-to=origin/main feature/branch
GH_STUB_DIR=$(cd "$REPO" && pwd -P) PATH="$BIN:$PATH" \
  run_hook pre-git-state-refresh.sh "git push origin feature/branch"
check "a branch tracking origin/main but never pushed skips gh" says "state=NONE (branch never pushed)"
git -C "$REPO" branch -q --unset-upstream feature/branch

git -C "$REPO" push -q origin feature/branch
GH_STUB_DIR=$(cd "$REPO" && pwd -P) PATH="$BIN:$PATH" \
  run_hook pre-git-state-refresh.sh "git push origin feature/branch"
check "pre-git-state-refresh asks gh about the payload repo's branch" says "state=MERGED"

GH_STUB_DIR=$(cd "$REPO" && pwd -P) PATH="$BIN:$PATH" \
  run_hook pre-git-state-refresh.sh "git -C \"$REPO\" push origin feature/branch"
check "pre-git-state-refresh reads a quoted git -C path" says "state=MERGED"

# The branch gate must see the payload repo's branch, not the caller's.
git -C "$REPO" checkout -q -B main
run_hook pre-commit-branch-gate.sh "git commit -m 'feat: x'"
check "pre-commit-branch-gate blocks main in the payload repo" \
  exited 2 says "Refusing to commit directly to 'main'"

git -C "$REPO" checkout -q -b feature/other
run_hook pre-commit-branch-gate.sh "git commit -m 'feat: x'"
check "pre-commit-branch-gate allows a feature branch" [ -z "$OUT" ]

run_hook pre-commit-branch-gate.sh "git -C \"$REPO\" -c core.x=y commit -m 'feat: x'"
check "pre-commit-branch-gate allows a quoted -C feature branch" [ -z "$OUT" ]

run_hook pre-commit-branch-gate.sh "cd $TEST_ROOT/nowhere && git commit -m 'feat: x'"
check "pre-commit-branch-gate blocks a commit outside any repo" exited 2 says "is not a git repo"

run_hook pre-commit-branch-gate.sh "git commit --help"
check "pre-commit-branch-gate skips --help" exited 0

# The push gate walks up from the resolved dir; a repo with no package.json
# and no *.tf is skipped silently, which proves it resolved somewhere real
# rather than walking up from the hook's own cwd.
run_hook pre-push-gate.sh "git push origin feature/other"
check "pre-push-gate skips a project with no manifest" [ -z "$OUT" ]

run_hook pre-push-gate.sh "cd $TEST_ROOT/nowhere && git push origin feature/other"
check "pre-push-gate blocks a push outside any repo" exited 2 says "[pre-push-gate]" says "is not a git repo"

echo
echo "== main checkout and worktree =="

# The main checkout sits on main, its worktree under .claude/worktrees/ on a
# feature branch, and CLAUDE_PROJECT_DIR stays on the main checkout, as it
# does for a session that entered the worktree.
git -C "$REPO" checkout -q main
WT="$REPO/.claude/worktrees/lane"
git -C "$REPO" worktree add -q -b feature/lane "$WT"

# run_in <cwd> <hook> <command>: runs the hook with CLAUDE_PROJECT_DIR on the main checkout.
run_in() {
  OUT=$(payload "$3" "$1" | (cd "$TEST_ROOT" && CLAUDE_PROJECT_DIR="$REPO" bash "$PROJECT_DIR/hooks/$2" 2>&1))
  STATUS=$?
}
run_in "$WT" pre-commit-branch-gate.sh "git commit -m 'feat: x'"
check "a commit from the worktree cwd checks the worktree's branch" exited 0
run_in "$REPO" pre-commit-branch-gate.sh "git -C \"$WT\" commit -m 'feat: x'"
check "git -C on the worktree beats a main-checkout cwd" exited 0
run_in "$WT" pre-commit-branch-gate.sh "git -C \"$REPO\" commit -m 'feat: x'"
check "git -C on the main checkout beats a worktree cwd" exited 2 says "'main'"
run_in "$REPO" pre-commit-branch-gate.sh "cd .claude/worktrees/lane && git commit -m 'feat: x'"
check "a relative cd into the worktree is followed" exited 0
run_in "" pre-commit-branch-gate.sh "git commit -m 'feat: x'"
check "without a cwd, CLAUDE_PROJECT_DIR names the main checkout" exited 2

finish
