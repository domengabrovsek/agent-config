#!/usr/bin/env bash
# Tests for scripts/worktree-prune.sh: the verdict for each worktree, and what
# --apply does with it.
#
# Every case runs against throwaway repos under a temp root, never a real
# checkout. Git runs with an empty global config so a host's commit signing,
# hooks path, or default branch name cannot leak into the fixtures.

set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$PROJECT_DIR/scripts/worktree-prune.sh"
TMP_ROOT=$(cd "${TMPDIR:-/tmp}" && pwd -P)
TEST_ROOT=$(cd "$(mktemp -d "$TMP_ROOT/worktree-prune-test.XXXXXX")" && pwd -P)
PASSED=0
FAILED=0
OUT=""
AGENT_REASON="claude agent agent-a1b2c3 (pid 4242)"
QUOTED_REASON='held by "agent" at C:\tmp, café'

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

cleanup() {
  case "$TEST_ROOT" in
    "$TMP_ROOT"/worktree-prune-test.*) rm -rf "$TEST_ROOT" ;;
    *) printf 'Refusing to clean unexpected test path: %s\n' "$TEST_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

pass() { PASSED=$((PASSED + 1)); printf 'ok - %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'not ok - %s\n' "$1" >&2; }

# add_worktree <repo> <branch> [option...]: a worktree at <repo>.wt/<branch> on
# a new branch cut from main's current tip.
add_worktree() {
  local repo="$1" branch="$2"
  shift 2
  git -C "$repo" worktree add -q "$@" -b "$branch" "$repo.wt/$branch" main
}

commit_on() {
  git -C "$1.wt/$2" commit -q --allow-empty -m "work on $2"
}

# merge_no_ff <repo> <branch>: land a branch the way GitHub's merge button does.
merge_no_ff() {
  git -C "$1" merge -q --no-ff -m "Merge $2" "$2"
}

# add_merged_dirty <repo> <branch> [option...]: a worktree landed by a merge
# commit that still holds an untracked file, so git refuses to remove it.
add_merged_dirty() {
  local repo="$1" branch="$2"
  add_worktree "$@"
  commit_on "$repo" "$branch"
  merge_no_ff "$repo" "$branch"
  : > "$repo.wt/$branch/untracked.txt"
}

# build_fixture <repo>: one repo with a worktree for each verdict. Order
# matters: fresh is cut before main moves on, and ff-merged is cut right before
# main fast-forwards onto it.
build_fixture() {
  local repo="$1" wt="$1.wt"
  git init -q -b main "$repo"
  git -C "$repo" commit -q --allow-empty -m "initial"

  add_worktree "$repo" fresh
  add_worktree "$repo" fresh-locked --lock
  git -C "$repo" worktree add -q --detach "$wt/detached" main
  git -C "$repo" worktree add -q --detach --lock "$wt/detached-locked" main

  add_worktree "$repo" unmerged
  commit_on "$repo" unmerged
  add_worktree "$repo" unmerged-locked --lock
  commit_on "$repo" unmerged-locked

  add_worktree "$repo" merged
  commit_on "$repo" merged
  merge_no_ff "$repo" merged
  add_worktree "$repo" merged-locked --lock
  commit_on "$repo" merged-locked
  merge_no_ff "$repo" merged-locked
  add_merged_dirty "$repo" merged-dirty
  # Agent hosts lock worktrees with a reason. Git's porcelain output C-quotes
  # the second one because it holds a quote, a backslash, and non-ASCII.
  add_merged_dirty "$repo" merged-dirty-locked --lock --reason "$AGENT_REASON"
  add_merged_dirty "$repo" merged-dirty-quoted --lock --reason "$QUOTED_REASON"

  # A merged worktree whose path has a space, beside a fresh one whose path
  # is the part before that space.
  add_worktree "$repo" twin
  git -C "$repo" worktree add -q -b twin-spaced "$wt/twin 2" main
  git -C "$wt/twin 2" commit -q --allow-empty -m "work on twin-spaced"
  merge_no_ff "$repo" twin-spaced

  add_worktree "$repo" ff-merged
  commit_on "$repo" ff-merged
  git -C "$repo" merge -q --ff-only ff-merged

  add_worktree "$repo" fresh-at-tip
  git -C "$repo" worktree add -q --force "$wt/on-main" main

  git init -q --bare -b main "$repo.origin.git"
  git -C "$repo" remote add origin "$repo.origin.git"
  add_worktree "$repo" upstream-gone
  commit_on "$repo" upstream-gone
  git -C "$wt/upstream-gone" push -q -u origin upstream-gone >/dev/null
  git -C "$repo.origin.git" branch -q -D upstream-gone
  git -C "$repo" fetch -q --prune origin
}

# run_prune <repo> [--apply]: sets OUT to the script's stdout.
run_prune() {
  local repo="$1"
  shift
  OUT=$(bash "$SCRIPT" "$@" --repo "$repo")
}

# verdict_of <path>: "<VERDICT> <reason>" from the last run's line for <path>.
# Matches the whole path, which may hold spaces, up to the branch= column.
verdict_of() {
  awk -v p="$1" 'index($0, " " p "  branch=") { r = $NF; sub(/^reason=/, "", r); print $1, r }' <<< "$OUT"
}

assert_verdict() {
  local name="$1" path="$2" want="$3" got
  got=$(verdict_of "$path")
  if [[ "$got" == "$want" ]]; then pass "$name"; else
    printf '    want: %s\n    got:  %s\n    output:\n%s\n' "$want" "${got:-no line}" "$OUT" >&2
    fail "$name"
  fi
}

# check <name> <command...>: passes when the command succeeds.
check() {
  local name="$1"
  shift
  if "$@"; then pass "$name"; else
    printf '    failed: %s\n    output:\n%s\n' "$*" "$OUT" >&2
    fail "$name"
  fi
}

output_has() { [[ "$OUT" == *"$1"* ]]; }
output_lacks() { [[ "$OUT" != *"$1"* ]]; }
absent() { [[ ! -e "$1" ]]; }
has_branch() { git -C "$1" show-ref --verify --quiet "refs/heads/$2"; }
no_branch() { ! has_branch "$1" "$2"; }
worktree_count() { git -C "$1" worktree list --porcelain | grep -c '^worktree '; }

# is_locked <repo> <path>: the porcelain listing marks the worktree locked.
is_locked() {
  git -C "$1" worktree list --porcelain | awk -v p="$2" '
    /^worktree / { cur = substr($0, 10) }
    /^locked/ && cur == p { found = 1 }
    END { exit !found }'
}

# lock_line_is <repo> <path> <want>: the worktree's porcelain "locked" line,
# with the reason as git prints it, equals <want>.
lock_line_is() {
  local got
  got=$(git -C "$1" worktree list --porcelain | awk -v p="$2" '
    /^worktree / { cur = substr($0, 10) }
    /^locked/ && cur == p { print }')
  [[ "$got" == "$3" ]]
}

echo "== verdicts (dry run) =="
REPO="$TEST_ROOT/dry-run"
WT="$REPO.wt"
build_fixture "$REPO"
BEFORE=$(worktree_count "$REPO")
run_prune "$REPO"
assert_verdict "a fresh worktree behind main is kept, not read as merged" \
  "$WT/fresh" "KEEP no-commits-of-its-own"
assert_verdict "a fresh worktree at main's tip is kept" \
  "$WT/fresh-at-tip" "KEEP no-commits-of-its-own"
assert_verdict "a fresh locked worktree is kept" \
  "$WT/fresh-locked" "KEEP no-commits-of-its-own"
assert_verdict "a fast-forward-merged branch is kept: its tip is on main's line" \
  "$WT/ff-merged" "KEEP no-commits-of-its-own"
assert_verdict "a branch landed by a merge commit is safe" \
  "$WT/merged" "SAFE merged-into-main"
assert_verdict "a locked branch landed by a merge commit is safe" \
  "$WT/merged-locked" "SAFE merged-into-main"
assert_verdict "a branch whose upstream is gone is safe" \
  "$WT/upstream-gone" "SAFE upstream-gone"
assert_verdict "an unmerged branch is kept" \
  "$WT/unmerged" "KEEP unmerged-or-active"
assert_verdict "a locked unmerged branch is kept" \
  "$WT/unmerged-locked" "KEEP locked-and-not-merged"
assert_verdict "a detached worktree is kept as detached" \
  "$WT/detached" "KEEP detached-HEAD-no-branch"
assert_verdict "a locked detached worktree is kept as detached" \
  "$WT/detached-locked" "KEEP detached-HEAD-no-branch"
check "a detached worktree lists no branch" output_has "$WT/detached  branch=?  reason="
assert_verdict "a lock reason git quotes leaves the row intact" \
  "$WT/merged-dirty-quoted" "SAFE merged-into-main"
assert_verdict "a second checkout of the default branch is kept" \
  "$WT/on-main" "KEEP default-branch-checkout"
assert_verdict "a path with a space is read whole" \
  "$WT/twin 2" "SAFE merged-into-main"
assert_verdict "the worktree at that path's first word keeps its own verdict" \
  "$WT/twin" "KEEP no-commits-of-its-own"
check "a dry run removes nothing" [ "$BEFORE" -eq "$(worktree_count "$REPO")" ]

echo
echo "== --apply =="
REPO="$TEST_ROOT/apply"
WT="$REPO.wt"
build_fixture "$REPO"
run_prune "$REPO" --apply
check "a fresh worktree survives --apply" test -d "$WT/fresh"
check "a fresh worktree keeps its branch" has_branch "$REPO" fresh
check "a fresh worktree at main's tip survives --apply" test -d "$WT/fresh-at-tip"
check "a fresh locked worktree stays locked" is_locked "$REPO" "$WT/fresh-locked"
check "an unmerged worktree survives --apply" test -d "$WT/unmerged"
check "a detached worktree survives --apply" test -d "$WT/detached"
check "a locked detached worktree stays locked" is_locked "$REPO" "$WT/detached-locked"
check "a merged worktree is removed" absent "$WT/merged"
check "a merged worktree's branch is deleted" no_branch "$REPO" merged
check "a locked merged worktree is unlocked and removed" absent "$WT/merged-locked"
check "an upstream-gone worktree is removed" absent "$WT/upstream-gone"
check "a merged worktree with a space in its path is removed" absent "$WT/twin 2"
check "the worktree at that path's first word survives" test -d "$WT/twin"
check "a dirty merged worktree stays on disk" test -d "$WT/merged-dirty"
check "a failed removal keeps the branch" has_branch "$REPO" merged-dirty
check "a failed removal is reported with git's reason" \
  output_has "-> not removed: '$WT/merged-dirty' contains modified or untracked files"
check "a failed removal is not reported as pruned" output_lacks "pruned (disk gone)"
check "a dirty locked worktree stays on disk" test -d "$WT/merged-dirty-locked"
check "a failed removal re-locks with the original reason" \
  lock_line_is "$REPO" "$WT/merged-dirty-locked" "locked $AGENT_REASON"
check "a reason git quotes is restored unchanged" \
  lock_line_is "$REPO" "$WT/merged-dirty-quoted" \
  'locked "held by \"agent\" at C:\\tmp, caf\303\251"'
check "a restored lock prints no warning" output_lacks "left unlocked"
check "the summary counts the failures apart from removals" \
  output_has "18 total, 4 removed, 11 kept, 3 failed"

printf '\n%s passed; %s failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
