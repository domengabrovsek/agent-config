#!/usr/bin/env bash
# Tests for scripts/worktree-prune.sh: the verdict for each worktree, and what
# --apply does with it.
#
# Every case runs against throwaway repos under a temp root, never a real
# checkout. Git runs with an empty global config so a host's commit signing,
# hooks path, or default branch name cannot leak into the fixtures.

set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
SCRIPT="$PROJECT_DIR/scripts/worktree-prune.sh"
harness_init -P worktree-prune
OUT=""
AGENT_REASON="claude agent agent-a1b2c3 (pid 4242)"
QUOTED_REASON='held by "agent" at C:\tmp, café'

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# add_worktree <repo> <branch> [option...]: a worktree at <repo>.wt/<branch> on
# a new branch cut from main's current tip.
add_worktree() {
  local repo="$1" branch="$2"
  shift 2
  git -C "$repo" worktree add -q "$@" -b "$branch" "$repo.wt/$branch" main
}

# commit_on <repo> <branch>: one commit adding <branch>.txt. Real content,
# because the squash-merge check compares trees and an empty commit adds none.
commit_on() {
  printf '%s\n' "$2" > "$1.wt/$2/$2.txt"
  git -C "$1.wt/$2" add "$2.txt"
  git -C "$1.wt/$2" commit -q -m "work on $2"
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
  printf '.claude/state/\n' > "$repo/.gitignore"
  git -C "$repo" add .gitignore
  git -C "$repo" commit -q -m "initial"

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
  printf 'twin-spaced\n' > "$wt/twin 2/twin-spaced.txt"
  git -C "$wt/twin 2" add twin-spaced.txt
  git -C "$wt/twin 2" commit -q -m "work on twin-spaced"
  merge_no_ff "$repo" twin-spaced

  # A squash merge lands the branch as a new commit, so its tip is not an
  # ancestor of main.
  add_worktree "$repo" squashed
  commit_on "$repo" squashed
  git -C "$repo" merge -q --squash squashed >/dev/null
  git -C "$repo" commit -q -m "Squash squashed"

  add_worktree "$repo" ff-merged
  commit_on "$repo" ff-merged
  git -C "$repo" merge -q --ff-only ff-merged

  # Ignored session state that `git worktree remove` would delete: one file
  # the main checkout lacks, one it holds with other content.
  add_worktree "$repo" merged-state
  commit_on "$repo" merged-state
  merge_no_ff "$repo" merged-state
  mkdir -p "$wt/merged-state/.claude/state/runs/merged-state"
  printf 'notes\n' > "$wt/merged-state/.claude/state/runs/merged-state/notes.md"
  add_worktree "$repo" merged-state-conflict
  commit_on "$repo" merged-state-conflict
  merge_no_ff "$repo" merged-state-conflict
  mkdir -p "$wt/merged-state-conflict/.claude/state/specs" "$repo/.claude/state/specs"
  printf 'worktree copy\n' > "$wt/merged-state-conflict/.claude/state/specs/spec.md"
  printf 'main copy\n' > "$repo/.claude/state/specs/spec.md"

  add_worktree "$repo" fresh-at-tip
  git -C "$repo" worktree add -q --force "$wt/on-main" main

  git init -q --bare -b main "$repo.origin.git"
  git -C "$repo" remote add origin "$repo.origin.git"
  # Pushed, then the remote branch deleted, then committed on again: the last
  # commit exists only here.
  add_worktree "$repo" upstream-gone
  commit_on "$repo" upstream-gone
  git -C "$wt/upstream-gone" push -q -u origin upstream-gone >/dev/null
  git -C "$repo.origin.git" branch -q -D upstream-gone
  printf 'later\n' >> "$wt/upstream-gone/upstream-gone.txt"
  git -C "$wt/upstream-gone" commit -q -am "unpushed work"
  # Landed on the remote's main by a merge the local main has not fetched.
  add_worktree "$repo" upstream-gone-pushed
  commit_on "$repo" upstream-gone-pushed
  git -C "$wt/upstream-gone-pushed" push -q -u origin upstream-gone-pushed >/dev/null
  git -C "$wt/upstream-gone-pushed" push -q origin upstream-gone-pushed:refs/heads/main >/dev/null
  git -C "$repo.origin.git" branch -q -D upstream-gone-pushed
  # Squash-merged into main, then the remote branch deleted.
  add_worktree "$repo" upstream-gone-squashed
  commit_on "$repo" upstream-gone-squashed
  git -C "$wt/upstream-gone-squashed" push -q -u origin upstream-gone-squashed >/dev/null
  git -C "$repo" merge -q --squash upstream-gone-squashed >/dev/null
  git -C "$repo" commit -q -m "Squash upstream-gone-squashed"
  git -C "$repo.origin.git" branch -q -D upstream-gone-squashed
  # Fast-forward-merged into main, then the remote branch deleted. Last,
  # because main fast-forwards onto it.
  add_worktree "$repo" upstream-gone-ff
  commit_on "$repo" upstream-gone-ff
  git -C "$wt/upstream-gone-ff" push -q -u origin upstream-gone-ff >/dev/null
  git -C "$repo" merge -q --ff-only upstream-gone-ff
  git -C "$repo.origin.git" branch -q -D upstream-gone-ff
  git -C "$repo" fetch -q --prune origin
}

# backdate <repo> <name>: age a worktree's index and HEAD past any idle limit.
backdate() {
  touch -t 202001010000 "$1/.git/worktrees/$2/index" "$1/.git/worktrees/$2/HEAD"
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

diagnose() { printf '    output:\n%s\n' "$OUT"; }
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
assert_verdict "a fast-forward-merged branch with no upstream is kept: its tip is on main's line" \
  "$WT/ff-merged" "KEEP no-commits-of-its-own"
assert_verdict "a branch landed by a merge commit is safe" \
  "$WT/merged" "SAFE merged-into-main"
assert_verdict "a squash-merged branch is safe" \
  "$WT/squashed" "SAFE squash-merged-into-main"
assert_verdict "an upstream-gone branch with unpushed commits is kept" \
  "$WT/upstream-gone" "KEEP upstream-gone-with-unpushed-commits"
assert_verdict "an upstream-gone branch whose commits are on a remote is safe" \
  "$WT/upstream-gone-pushed" "SAFE upstream-gone"
assert_verdict "an upstream-gone branch squash-merged into main is safe" \
  "$WT/upstream-gone-squashed" "SAFE squash-merged-into-main"
assert_verdict "an upstream-gone branch fast-forward-merged into main is safe" \
  "$WT/upstream-gone-ff" "SAFE upstream-gone"
assert_verdict "an unmerged branch is kept" \
  "$WT/unmerged" "KEEP unmerged-or-active"
assert_verdict "a detached worktree is kept as detached" \
  "$WT/detached" "KEEP detached-HEAD-no-branch"
check "a detached worktree lists no branch" says "$WT/detached  branch=?  reason="
assert_verdict "a locked fresh worktree is kept as locked" \
  "$WT/fresh-locked" "KEEP locked"
assert_verdict "a locked merged worktree is kept as locked" \
  "$WT/merged-locked" "KEEP locked"
assert_verdict "a locked unmerged worktree is kept as locked" \
  "$WT/unmerged-locked" "KEEP locked"
assert_verdict "a locked detached worktree is kept as locked" \
  "$WT/detached-locked" "KEEP locked"
assert_verdict "a lock reason git quotes leaves the row intact" \
  "$WT/merged-dirty-quoted" "KEEP locked"
assert_verdict "a second checkout of the default branch is kept" \
  "$WT/on-main" "KEEP default-branch-checkout"
assert_verdict "a path with a space is read whole" \
  "$WT/twin 2" "SAFE merged-into-main"
assert_verdict "the worktree at that path's first word keeps its own verdict" \
  "$WT/twin" "KEEP no-commits-of-its-own"
check "a dry run removes nothing" [ "$BEFORE" -eq "$(worktree_count "$REPO")" ]

run_prune "$REPO" --force-locked
assert_verdict "--force-locked judges a locked merged worktree on its branch" \
  "$WT/merged-locked" "SAFE merged-into-main"
assert_verdict "--force-locked still keeps a locked unmerged worktree" \
  "$WT/unmerged-locked" "KEEP unmerged-or-active"

run_prune "$REPO" --min-idle 30
assert_verdict "--min-idle keeps a merged worktree touched recently" \
  "$WT/merged" "KEEP active-in-last-30m"
backdate "$REPO" merged
run_prune "$REPO" --min-idle 30
assert_verdict "--min-idle judges an idle worktree on its branch" \
  "$WT/merged" "SAFE merged-into-main"

echo
echo "== --apply =="
REPO="$TEST_ROOT/apply"
WT="$REPO.wt"
build_fixture "$REPO"
run_prune "$REPO" --apply
check "a fresh worktree survives --apply" test -d "$WT/fresh"
check "a fresh worktree keeps its branch" has_branch "$REPO" fresh
check "a fresh worktree at main's tip survives --apply" test -d "$WT/fresh-at-tip"
check "an unmerged worktree survives --apply" test -d "$WT/unmerged"
check "a detached worktree survives --apply" test -d "$WT/detached"
check "a merged worktree is removed" absent "$WT/merged"
check "a merged worktree's branch is deleted" no_branch "$REPO" merged
check "a locked merged worktree survives --apply" test -d "$WT/merged-locked"
check "a locked merged worktree stays locked" is_locked "$REPO" "$WT/merged-locked"
check "a locked fresh worktree stays locked" is_locked "$REPO" "$WT/fresh-locked"
check "an upstream-gone worktree with unpushed commits survives" test -d "$WT/upstream-gone"
check "an upstream-gone branch with unpushed commits is kept" has_branch "$REPO" upstream-gone
check "an upstream-gone worktree whose commits are on a remote is removed" absent "$WT/upstream-gone-pushed"
check "its branch is deleted" no_branch "$REPO" upstream-gone-pushed
check "an upstream-gone squash-merged worktree is removed" absent "$WT/upstream-gone-squashed"
check "its branch is deleted" no_branch "$REPO" upstream-gone-squashed
check "an upstream-gone fast-forward-merged worktree is removed" absent "$WT/upstream-gone-ff"
check "a squash-merged worktree is removed" absent "$WT/squashed"
check "a squash-merged worktree's branch is deleted" no_branch "$REPO" squashed
check "a merged worktree with a space in its path is removed" absent "$WT/twin 2"
check "the worktree at that path's first word survives" test -d "$WT/twin"
check "a dirty merged worktree stays on disk" test -d "$WT/merged-dirty"
check "a failed removal keeps the branch" has_branch "$REPO" merged-dirty
check "a failed removal is reported with git's reason" \
  says "-> not removed: '$WT/merged-dirty' contains modified or untracked files"
check "a worktree with ignored state is removed" absent "$WT/merged-state"
check "its ignored state is copied into the main checkout" \
  grep -qx notes "$REPO/.claude/state/runs/merged-state/notes.md"
check "a worktree whose state differs from the main checkout stays" test -d "$WT/merged-state-conflict"
check "the differing state is reported" \
  says "-> not removed: .claude/state/specs/spec.md differs from the main checkout"
check "the main checkout's copy is untouched" grep -qx "main copy" "$REPO/.claude/state/specs/spec.md"
check "the summary counts the failures apart from removals" \
  says "24 total, 7 removed, 15 kept, 2 failed"

echo
echo "== --apply --force-locked =="
REPO="$TEST_ROOT/force-locked"
WT="$REPO.wt"
build_fixture "$REPO"
run_prune "$REPO" --apply --force-locked
check "a locked merged worktree is unlocked and removed" absent "$WT/merged-locked"
check "a locked fresh worktree stays locked" is_locked "$REPO" "$WT/fresh-locked"
check "a locked unmerged worktree stays locked" is_locked "$REPO" "$WT/unmerged-locked"
check "a dirty locked worktree stays on disk" test -d "$WT/merged-dirty-locked"
check "a failed removal re-locks with the original reason" \
  lock_line_is "$REPO" "$WT/merged-dirty-locked" "locked $AGENT_REASON"
check "a reason git quotes is restored unchanged" \
  lock_line_is "$REPO" "$WT/merged-dirty-quoted" \
  'locked "held by \"agent\" at C:\\tmp, caf\303\251"'
check "a restored lock prints no warning" omits "left unlocked"
check "the summary counts the forced removals" \
  says "24 total, 8 removed, 12 kept, 4 failed"

echo
echo "== SessionEnd hook =="
REPO="$TEST_ROOT/hook"
WT="$REPO.wt"
build_fixture "$REPO"
PROJECT="$TEST_ROOT/project"
stub "$PROJECT/scripts" worktree-prune.sh <<'STUB'
#!/bin/bash
: > "$(dirname "$0")/ran"
STUB
run_hook() {
  (cd "$REPO" && CLAUDE_PROJECT_DIR="$PROJECT" bash "$PROJECT_DIR/hooks/worktree-cleanup.sh")
}
run_hook
check "the hook never runs the project's own prune script" absent "$PROJECT/scripts/ran"
check "the hook keeps a merged worktree touched in the last 30 minutes" test -d "$WT/merged"
backdate "$REPO" merged
run_hook
check "the hook removes a merged worktree idle for 30 minutes" absent "$WT/merged"
check "the hook keeps a locked worktree" test -d "$WT/merged-locked"

finish
