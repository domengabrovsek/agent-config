#!/bin/bash
# Tests for scripts/worktree-fill-protected.sh: it copies only listed
# protected files from the main checkout, refuses symlinks on either side,
# refuses repos outside the dev root, and ignores the caller's HOME and PATH.
# Worktrees come from the real repo-worktree.sh against throwaway repos.

set -uo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
harness_init -P worktree-fill-protected

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
REAL_HOME="$TEST_ROOT/home"
DEV="$REAL_HOME/dev"
mkdir -p "$DEV"
# The script fixes HOME from the user database, so the suite runs a copy whose
# HOME line points at the throwaway home, and a caller HOME that must not matter.
export HOME="$TEST_ROOT/caller-home"
mkdir -p "$HOME"
SCRIPT="$TEST_ROOT/worktree-fill-protected.sh"
sed -e "s|^HOME=\$(passwd_home)\$|HOME=\"$REAL_HOME\"|" \
  "$PROJECT_DIR/scripts/worktree-fill-protected.sh" > "$SCRIPT"
chmod +x "$SCRIPT"
NEW_WT="$PROJECT_DIR/scripts/repo-worktree.sh"

# A decoy git first on PATH proves the script runs no git.
DECOY="$TEST_ROOT/decoy"
stub "$DECOY" git <<'EOF'
#!/bin/bash
echo ran >> "$(dirname "$0")/git-ran"
exec /usr/bin/env git "$@"
EOF

# seed_repo <dir>: a repo tracking a hook, a skill, settings, and a plain file.
seed_repo() {
  mkdir -p "$1/.husky" "$1/.claude/skills/x" "$1/src"
  printf 'npm test\n' > "$1/.husky/pre-commit"
  chmod +x "$1/.husky/pre-commit"
  printf 'skill\n' > "$1/.claude/skills/x/SKILL.md"
  printf '{}\n' > "$1/.claude/settings.json"
  printf 'plain\n' > "$1/src/a.txt"
  make_repo "$1"
}

# new_worktree <repo> <slug>: creates the worktree, sets WT, and leaves the fill list.
new_worktree() {
  HOME="$REAL_HOME" "$NEW_WT" "$1" "$2" --base main >/dev/null 2>&1
  WT="$1/.claude/worktrees/$2"
  [ -d "$WT" ] || { echo "setup: no worktree at $WT" >&2; exit 1; }
}

fill() { PATH="$DECOY:$PATH" "$SCRIPT" "$@"; }
list_of() { printf '%s\n' "$(git -C "$1" rev-parse --path-format=absolute --git-dir)/fill-protected"; }

REPO="$DEV/repo"
seed_repo "$REPO"

new_worktree "$REPO" happy
expect_exit --says "copied 3" "fills every listed protected file" 0 fill "$WT"
check "the hook matches the main checkout" cmp -s "$REPO/.husky/pre-commit" "$WT/.husky/pre-commit"
check "the hook stays executable" [ -x "$WT/.husky/pre-commit" ]
check "the settings file is not executable" [ ! -x "$WT/.claude/settings.json" ]
check "the worktree is clean after the fill" [ -z "$(git -C "$WT" status --porcelain)" ]
check "the fill list is removed" [ ! -e "$(list_of "$WT")" ]
check "no temp file is left" [ -z "$(find "$WT" -name '.fill-protected.*')" ]
check "runs no git" [ ! -e "$DECOY/git-ran" ]
expect_exit --says "no file list" "a second run finds no list" 1 fill "$WT"

# A symlinked destination directory cannot carry a write outside the worktree.
VICTIM="$TEST_ROOT/victim"
mkdir -p "$VICTIM"
new_worktree "$REPO" linkdir
rm -rf "$WT/.claude"
ln -s "$VICTIM" "$WT/.claude"
expect_exit --says ".claude/skills/x/SKILL.md" "skips paths under a symlinked dir" 3 fill "$WT"
check "nothing lands in the symlink target" [ -z "$(ls -A "$VICTIM")" ]
check "the skip prints a ! command" says "checkout HEAD --"
check "the unlinked hook is still filled" [ -f "$WT/.husky/pre-commit" ]

# A planted symlink at the destination file is not followed or replaced.
printf 'keep\n' > "$VICTIM/target"
new_worktree "$REPO" linkfile
mkdir -p "$WT/.husky"
ln -s "$VICTIM/target" "$WT/.husky/pre-commit"
expect_exit --says ".husky/pre-commit" "skips a symlinked destination file" 3 fill "$WT"
check "the symlink target keeps its content" [ "$(cat "$VICTIM/target")" = keep ]

# List entries that are not protected, or escape the tree, are skipped.
new_worktree "$REPO" badlist
printf '%s\n' src/a.txt ../../../victim/target .claude/skills/../../src/a.txt > "$(list_of "$WT")"
expect_exit --says "src/a.txt" "skips unprotected and escaping entries" 3 fill "$WT"
check "the target stays untouched" [ "$(cat "$VICTIM/target")" = keep ]

# A symlinked source inside the main checkout is not trusted.
LINKSRC="$DEV/linksrc"
seed_repo "$LINKSRC"
new_worktree "$LINKSRC" src
rm -rf "$LINKSRC/.claude/skills/x"
mkdir -p "$TEST_ROOT/agent-skill"
printf 'skill\n' > "$TEST_ROOT/agent-skill/SKILL.md"
ln -s "$TEST_ROOT/agent-skill" "$LINKSRC/.claude/skills/x"
expect_exit --says ".claude/skills/x/SKILL.md" "skips a source under a symlinked dir" 3 fill "$WT"
check "the linked skill is not copied" [ ! -e "$WT/.claude/skills/x/SKILL.md" ]

# Refusals before any copy.
OUTSIDE="$TEST_ROOT/outside"
seed_repo "$OUTSIDE"
new_worktree "$OUTSIDE" out
expect_exit --says "outside" "refuses a repo outside the dev root" 1 fill "$WT"
check "the outside worktree stays unfilled" [ ! -e "$WT/.husky/pre-commit" ]

new_worktree "$REPO" viapath
ln -s "$REPO" "$DEV/alias"
expect_exit --says "real directory path" "refuses a path through a symlink" 1 fill "$DEV/alias/.claude/worktrees/viapath"
expect_exit --says "absolute" "refuses a relative path" 1 fill "repo/.claude/worktrees/viapath"
expect_exit --says "not under" "refuses a path outside .claude/worktrees" 1 fill "$REPO/src"
mkdir -p "$REPO/.claude/worktrees/plain"
expect_exit --says "not a linked worktree" "refuses a plain directory" 1 fill "$REPO/.claude/worktrees/plain"
expect_exit "refuses extra arguments" 2 fill "$WT" extra
expect_exit --says "Usage:" "--help prints the header" 0 fill --help

finish
