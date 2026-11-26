#!/bin/bash -p
# Copies sandbox-protected files from a main checkout into one of its new
# worktrees. Agents may run it outside the sandbox through one
# excludedCommands entry, `~/.agents/scripts/worktree-fill-protected.sh *`,
# after repo-worktree.sh exits 4.
#
# Usage: worktree-fill-protected.sh <main-checkout>/.claude/worktrees/<slug>
#
# The sandbox denies agent writes to .husky and to .claude settings, hooks,
# skills, agents, and commands under ~/dev, so the main checkout's copies of
# those files are user-trusted. The script copies each listed path from the
# main checkout to the same path in the worktree, so the agent never chooses
# the content. repo-worktree.sh writes the list to the worktree's admin dir
# and lists only files that match the worktree's HEAD. The list is untrusted:
# a wrong entry can only copy another trusted file.
#
# The script runs no git, so no repo config, hook, or filter applies. HOME and
# PATH are fixed, and bash -p skips BASH_ENV, because agents set the caller's
# environment. It refuses symlinks on both sides and re-checks each written
# file, so a planted or swapped link cannot redirect a write.
#
# Exit codes: 0 copied all, 1 refused, 2 usage error, 3 some paths skipped.

set -euo pipefail
PATH=/usr/bin:/bin
export PATH
umask 022

die() { echo "worktree-fill-protected: $1" >&2; exit 1; }

# passwd_home: prints the account's home from the user database, not $HOME.
passwd_home() {
  local user
  user=$(id -un)
  case "$user" in ''|*[!A-Za-z0-9._-]*) die "unexpected user name: $user" ;; esac
  eval "printf '%s\n' ~$user"
}

# The test suite rewrites these two lines.
HOME=$(passwd_home)
DEV_ROOT="$HOME/dev"

case "${1:-}" in -h|--help) sed -n '2,/^[^#]/s/^# \{0,1\}//p' "$0"; exit 0 ;; esac
[ $# -eq 1 ] || { echo "Usage: worktree-fill-protected.sh <worktree>" >&2; exit 2; }
WT="$1"

# real_dir_under <base> <relative dir>: succeeds when every component of the
# directory exists under base as a real directory, not a symlink.
real_dir_under() {
  local path="$1" part rest="$2"
  while [ -n "$rest" ]; do
    part="${rest%%/*}"
    if [ "$part" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
    path="$path/$part"
    [ -d "$path" ] && [ ! -L "$path" ] || return 1
  done
}

# The worktree must be <main>/.claude/worktrees/<slug> under ~/dev, spelled
# as its real path, so no symlink sits anywhere in it.
case "$WT" in /*) ;; *) die "worktree path must be absolute: $WT" ;; esac
[ -d "$WT" ] && [ "$(cd -P -- "$WT" && pwd -P)" = "$WT" ] || die "worktree path is not a real directory path: $WT"
SLUG="${WT##*/}"
case "$SLUG" in ''|*[!A-Za-z0-9._-]*|.|..) die "bad worktree name: $SLUG" ;; esac
MAIN="${WT%/.claude/worktrees/"$SLUG"}"
[ "$MAIN" != "$WT" ] || die "not under <main>/.claude/worktrees/: $WT"
DEV_REAL=$(cd -P -- "$DEV_ROOT" 2>/dev/null && pwd -P) || die "no $DEV_ROOT"
case "$MAIN/" in "$DEV_REAL"/*) ;; *) die "main checkout is outside $DEV_REAL: $MAIN" ;; esac
[ -d "$MAIN/.git" ] && [ ! -L "$MAIN/.git" ] || die "not a main checkout: $MAIN"

[ -f "$WT/.git" ] && [ ! -L "$WT/.git" ] || die "not a linked worktree: $WT"
ADMIN=$(sed -n '1s/^gitdir: //p' "$WT/.git")
NAME="${ADMIN##*/}"
case "$NAME" in ''|*[!A-Za-z0-9._-]*|.|..) die "bad worktree admin dir: $ADMIN" ;; esac
[ "$ADMIN" = "$MAIN/.git/worktrees/$NAME" ] || die "worktree belongs to another repo: $ADMIN"
real_dir_under "$MAIN" ".git/worktrees/$NAME" || die "worktree admin dir is not a real directory: $ADMIN"
LIST="$ADMIN/fill-protected"
[ -f "$LIST" ] && [ ! -L "$LIST" ] || die "no file list at $LIST; run repo-worktree.sh first"

# Mirrors the ~/dev write denies in settings.json and PROTECTED_RE in repo-worktree.sh.
PROTECTED_RE='(^|/)\.husky(/|$)|(^|/)\.claude/(settings\.json|settings\.local\.json)$|(^|/)\.claude/(hooks|skills|agents|commands)/'

# enter_dest <relative dir>: cds into WT/<dir>, creating each component, and
# checks the real path at every step.
enter_dest() {
  local want="$WT" part rest="$1"
  cd -P -- "$WT" && [ "$(pwd -P)" = "$want" ] || return 1
  while [ -n "$rest" ]; do
    part="${rest%%/*}"
    if [ "$part" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
    if [ ! -e "$part" ] && [ ! -L "$part" ]; then mkdir -- "$part" || return 1; fi
    [ -d "$part" ] && [ ! -L "$part" ] || return 1
    cd -P -- "$part" || return 1
    want="$want/$part"
    [ "$(pwd -P)" = "$want" ] || return 1
  done
}

# GNU stat first: its -f prints file system status instead of failing.
link_count() { stat -c %h -- "$1" 2>/dev/null || stat -f %l -- "$1"; }

# copy_one <relative path>: copies MAIN/<path> to WT/<path>. It writes a temp
# file, renames it into place, then checks the result is a lone regular file
# equal to the source, and removes it otherwise.
copy_one() {
  local path="$1" dir name src mode tmp
  printf '%s\n' "$path" | grep -Eq "$PROTECTED_RE" || return 1
  case "/$path/" in *//*|*/./*|*/../*) return 1 ;; esac
  dir="${path%/*}"
  [ "$dir" != "$path" ] || dir=""
  name="${path##*/}"
  src="$MAIN/$path"
  { [ -z "$dir" ] || real_dir_under "$MAIN" "$dir"; } || return 1
  [ -f "$src" ] && [ ! -L "$src" ] || return 1
  mode=644
  [ ! -x "$src" ] || mode=755
  (
    enter_dest "$dir" || exit 1
    [ ! -e "$name" ] && [ ! -L "$name" ] || exit 1
    tmp=$(mktemp "./.fill-protected.XXXXXX") || exit 1
    cat -- "$src" > "$tmp" && chmod "$mode" "$tmp" && mv -f -- "$tmp" "$name" || { rm -f -- "$tmp"; exit 1; }
    if [ -L "$name" ] || [ ! -f "$name" ] || [ "$(link_count "$name")" != 1 ] || ! cmp -s -- "$src" "$name"; then
      rm -f -- "$name"
      exit 1
    fi
  )
}

COPIED=0
SKIPPED=()
while IFS= read -r path || [ -n "$path" ]; do
  [ -n "$path" ] || continue
  if copy_one "$path"; then COPIED=$((COPIED + 1)); else SKIPPED+=("$path"); fi
done < "$LIST"
rm -f -- "$LIST"

echo "worktree-fill-protected: copied $COPIED protected file(s) into $WT" >&2
if [ ${#SKIPPED[@]} -gt 0 ]; then
  {
    echo "worktree-fill-protected: skipped these, because they are missing, unsafe, or not protected:"
    printf '  %s\n' "${SKIPPED[@]}"
    echo "Check them out yourself outside the sandbox, with the ! prefix in a session:"
    printf '  ! git -C %q checkout HEAD --' "$WT"
    printf ' %q' "${SKIPPED[@]}"
    printf '\n'
  } >&2
  exit 3
fi
