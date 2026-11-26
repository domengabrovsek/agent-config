#!/bin/bash
# Tests for scripts/repo-worktree.sh: where the worktree lands, which base it
# uses, what it refuses, the repo registry, and that .git/config stays as it
# was. Every case runs against a throwaway clone of a bare remote under the
# harness temp dir, with an empty global git config and a throwaway HOME.

set -uo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
SCRIPT="$PROJECT_DIR/scripts/repo-worktree.sh"
harness_init -P repo-worktree

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export HOME="$TEST_ROOT/home"
mkdir -p "$HOME"
REGISTRY="$HOME/.cache/agent/worktree-repos"

REMOTE="$TEST_ROOT/remote.git"
SEED="$TEST_ROOT/seed"
CLONE="$TEST_ROOT/clone"

git init -q --bare -b main "$REMOTE"
make_repo "$SEED"
printf 'one\n' > "$SEED/file.txt"
git -C "$SEED" add file.txt
git -C "$SEED" commit -q -m "feat: one"
git -C "$SEED" remote add origin "$REMOTE"
git -C "$SEED" push -q origin main
git -C "$SEED" switch -q -c release
printf 'release\n' > "$SEED/release.txt"
git -C "$SEED" add release.txt
git -C "$SEED" commit -q -m "feat: release"
git -C "$SEED" push -q origin release
git clone -q "$REMOTE" "$CLONE"
CONFIG_BEFORE=$(cat "$CLONE/.git/config")

# Main moves on after the clone, so a fresh fetch is the only way to see it.
git -C "$SEED" switch -q main
printf 'two\n' > "$SEED/file.txt"
git -C "$SEED" commit -q -am "feat: two"
git -C "$SEED" push -q origin main
REMOTE_MAIN=$(git -C "$SEED" rev-parse main)
REMOTE_RELEASE=$(git -C "$SEED" rev-parse release)

last_line() { printf '%s\n' "$OUT" | tail -n 1; }
head_of() { git -C "$1" rev-parse HEAD; }
branch_of() { git -C "$1" branch --show-current; }

# Default base: origin's default branch, freshly fetched, on feat/<slug>.
expect_exit "creates a worktree from the default branch" 0 "$SCRIPT" "$CLONE" first
WT="$CLONE/.claude/worktrees/first"
check "prints the worktree path last" [ "$(last_line)" = "$WT" ]
check "worktree sits on feat/<slug>" [ "$(branch_of "$WT")" = "feat/first" ]
check "worktree starts at the fetched remote tip" [ "$(head_of "$WT")" = "$REMOTE_MAIN" ]
check "main checkout ignores .claude/worktrees" git -C "$CLONE" check-ignore -q .claude/worktrees/x

# --base picks another remote branch, --branch overrides the name.
expect_exit "creates a worktree from --base" 0 "$SCRIPT" "$CLONE" second --base release --branch fix/second
WT2="$CLONE/.claude/worktrees/second"
check "--base worktree starts at origin/release" [ "$(head_of "$WT2")" = "$REMOTE_RELEASE" ]
check "--branch sets the branch name" [ "$(branch_of "$WT2")" = "fix/second" ]

# A linked worktree path resolves to the main checkout.
expect_exit "accepts a linked worktree path" 0 "$SCRIPT" "$WT/" third
check "linked input lands under the main checkout" [ "$(last_line)" = "$CLONE/.claude/worktrees/third" ]

# Refusals.
expect_exit --says "already exists" "refuses an existing slug" 1 "$SCRIPT" "$CLONE" first
expect_exit --says "already exists" "refuses an existing branch" 1 "$SCRIPT" "$CLONE" other --branch feat/first
expect_exit --says "no such directory" "refuses a missing repo" 1 "$SCRIPT" "$TEST_ROOT/nope" slug
mkdir -p "$TEST_ROOT/plain"
expect_exit --says "not inside a git work tree" "refuses a non-repo" 1 "$SCRIPT" "$TEST_ROOT/plain" slug
expect_exit "refuses a bad slug" 2 "$SCRIPT" "$CLONE" "Bad Slug"
printf 'dirty\n' >> "$CLONE/file.txt"
expect_exit --says "uncommitted changes" "a dirty main checkout only gets a note" 0 "$SCRIPT" "$CLONE" dirty
check "the dirty main checkout keeps its change" grep -q dirty "$CLONE/file.txt"
check "the new worktree starts clean" [ -z "$(git -C "$CLONE/.claude/worktrees/dirty" status --porcelain)" ]
git -C "$CLONE" checkout -q -- file.txt

# Registry: one line per main checkout, however many worktrees it has.
check "registry lists the main checkout" grep -Fxq "$CLONE" "$REGISTRY"
check "registry dedups the main checkout" [ "$(grep -Fxc "$CLONE" "$REGISTRY")" -eq 1 ]
check "registry holds only that line" [ "$(wc -l < "$REGISTRY" | tr -d ' ')" -eq 1 ]

# No upstream and no branch.* config for the new branches; the clone wrote main's.
for b in feat/first fix/second feat/third; do
  check "no branch config for $b" not git -C "$CLONE" config --get-regexp "^branch\\.$b\\."
done
check ".git/config unchanged" [ "$(cat "$CLONE/.git/config")" = "$CONFIG_BEFORE" ]

# A base that tracks a sandbox-protected path gets every other file, and the
# matching protected files are listed for worktree-fill-protected.sh.
HUSKY="$TEST_ROOT/husky"
mkdir -p "$HUSKY/.husky" "$HUSKY/.claude/skills/x" "$HUSKY/src/.husky-notes"
printf 'npm test\n' > "$HUSKY/.husky/pre-commit"
printf 'x\n' > "$HUSKY/.claude/skills/x/SKILL.md"
printf 'x\n' > "$HUSKY/src/.husky-notes/readme"
make_repo "$HUSKY"
GUARDED="$HUSKY/.claude/worktrees/guarded"
expect_exit --says "worktree-fill-protected.sh" "a protected base exits 4" 4 "$SCRIPT" "$HUSKY" guarded --base main
check "a protected base still prints the path last" [ "$(last_line)" = "$GUARDED" ]
check "the unprotected look-alike is checked out" [ -f "$GUARDED/src/.husky-notes/readme" ]
check "the protected files are left out" [ ! -e "$GUARDED/.husky/pre-commit" ] && [ ! -e "$GUARDED/.claude/skills/x/SKILL.md" ]
FILL_LIST="$HUSKY/.git/worktrees/guarded/fill-protected"
check "the fill list names the matching protected files" \
  [ "$(sort "$FILL_LIST" | tr '\n' ' ')" = ".claude/skills/x/SKILL.md .husky/pre-commit " ]
check "no ! command when nothing drifted" omits "checkout HEAD --"

# A protected file the main checkout changed is left for the user.
printf 'changed\n' > "$HUSKY/.husky/pre-commit"
expect_exit --says "checkout HEAD -- .husky/pre-commit" "a drifted protected file gets a ! command" 4 \
  "$SCRIPT" "$HUSKY" drifted --base main
check "the drifted file stays off the fill list" \
  [ "$(cat "$HUSKY/.git/worktrees/drifted/fill-protected")" = ".claude/skills/x/SKILL.md" ]
git -C "$HUSKY" checkout -q -- .husky/pre-commit

ONLY="$TEST_ROOT/only-protected"
mkdir -p "$ONLY/.claude/skills/y"
printf 'y\n' > "$ONLY/.claude/skills/y/SKILL.md"
make_repo "$ONLY"
expect_exit "a base with only protected files still exits 4" 4 "$SCRIPT" "$ONLY" only --base main
check "its fill list names the skill" [ "$(cat "$ONLY/.git/worktrees/only/fill-protected")" = ".claude/skills/y/SKILL.md" ]

expect_exit "--allow-protected creates it in full" 0 "$SCRIPT" "$HUSKY" full --base main --allow-protected
check "the protected file is checked out" [ -f "$HUSKY/.claude/worktrees/full/.husky/pre-commit" ]

expect_exit --says "Usage:" "--help prints the header" 0 "$SCRIPT" --help

finish
