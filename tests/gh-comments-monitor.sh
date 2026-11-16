#!/bin/bash
# Tests for skills/pr-comments/scripts/gh-comments-monitor.sh. A stub gh on
# PATH serves PR 7 with one bot comment and reports the PR merged, so each run
# ends after one poll. The stub logs the directory every call ran in.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
MONITOR="$PROJECT_DIR/skills/pr-comments/scripts/gh-comments-monitor.sh"

harness_init -P gh-comments-monitor TEST_DIR

stub "$TEST_DIR/bin" gh <<'STUB'
#!/bin/bash
pwd -P >> "$GH_CALLS"
case "$*" in
  "api user"*) echo "me" ;;
  "pr view --json number"*) echo 7 ;;
  "pr view 7 --json state"*) echo MERGED ;;
  *pulls/7/comments*) echo "inline|101|lint[bot]|bot|https://example.test/c/101" ;;
  api*) ;;
  *) exit 1 ;;
esac
STUB
export PATH="$TEST_DIR/bin:$PATH" PR_COMMENTS_INTERVAL=0 GH_CALLS="$TEST_DIR/gh-calls"

HOME_REPO="$TEST_DIR/home"
CHILD="$TEST_DIR/child"
make_repo "$HOME_REPO"
make_repo "$CHILD"
git -C "$CHILD" branch -q feat/x
git -C "$CHILD" worktree add -q "$CHILD/.claude/worktrees/x" feat/x
WT="$CHILD/.claude/worktrees/x"
SEEN="$CHILD/.claude/state/runs/feat-x/comments-seen"

run_monitor() { (cd "$1" && shift && bash "$MONITOR" "$@"); }
only_in() { ! grep -vqx "$1" "$GH_CALLS"; }

echo "== --repo from another repo =="
: > "$GH_CALLS"
expect_exit --says "comment|inline|101|lint[bot]|bot|" "a home-repo cwd monitors the child PR" 0 \
  run_monitor "$HOME_REPO" --repo "$WT"
check "it reports the merged PR" says "pr-closed|MERGED"
check "every gh call runs in the child worktree" only_in "$WT"
check "seen IDs land in the child's main checkout" test -s "$SEEN"
check "the home repo gets no state" not test -e "$HOME_REPO/.claude/state"
check "the worktree gets no state" not test -e "$WT/.claude/state"

expect_exit "a re-armed monitor does not repeat a comment" 0 run_monitor "$HOME_REPO" --repo "$WT" 7
check "the repeat stays silent" omits "comment|"

echo
echo "== cwd is the target =="
rm -f "$SEEN"
expect_exit --says "comment|inline|101" "without --repo the cwd is the target" 0 run_monitor "$WT"
check "seen IDs still land in the main checkout" test -s "$SEEN"

echo
echo "== bad input =="
expect_exit --says "error|no-repo|" "a missing repo path fails" 1 run_monitor "$HOME_REPO" --repo "$TEST_DIR/missing"
expect_exit --says "error|no-repo|" "--repo without a value fails" 1 run_monitor "$HOME_REPO" --repo

finish
