#!/bin/bash
# Creates a task worktree in any local repo, not only the session's own, so a
# session started in one repo can branch work in a sibling repo.
#
# The worktree lands at <main-checkout>/.claude/worktrees/<slug> on a new
# branch cut from the fetched base, with no upstream. The script never writes
# .git/config, so push with `git push origin <branch>`. A linked worktree path
# maps to its main checkout. Changes in the main checkout stay untouched; the
# script only notes them on stderr.
#
# The main checkout path is appended once to ~/.cache/agent/worktree-repos,
# one absolute path per line. The SessionEnd cleanup hook reads that file and
# prunes merged worktrees in each listed repo.
#
# The sandbox denies writes to .husky and to .claude settings, hooks, skills,
# agents, and commands under ~/dev. For a base that tracks any of them, the
# script checks out every other file, lists the protected files that match the
# main checkout's copies, and exits 4. The caller then runs
# worktree-fill-protected.sh <worktree>, which copies them outside the sandbox.
# Protected files that differ from the main checkout get a ! command for the
# user. --allow-protected does a plain checkout, for a run outside the sandbox.
#
# Usage:
#   repo-worktree.sh <repo-path> <slug> [--base <ref>] [--branch <name>] [--allow-protected]
#
#   --base <ref>       branch on origin, or a local ref (default: origin's default branch)
#   --branch <name>    new branch name (default: feat/<slug>)
#   --allow-protected  skip the protected-path check, for a run outside the sandbox
#
# Prints the worktree path as the last stdout line.
# Exit codes: 0 created, 1 refused or git failed, 2 usage error,
# 4 created without its protected files; run worktree-fill-protected.sh next.

set -euo pipefail

usage_error() {
  echo "repo-worktree: $1" >&2
  echo "Usage: repo-worktree.sh <repo-path> <slug> [--base <ref>] [--branch <name>]" >&2
  exit 2
}

die() {
  echo "repo-worktree: $1" >&2
  exit 1
}

REPO_ARG=""
SLUG=""
ALLOW_PROTECTED=0
BASE=""
BRANCH=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,/^[^#]/s/^# \{0,1\}//p' "$0"; exit 0 ;;
    --base) [ $# -ge 2 ] || usage_error "--base needs a ref"; BASE="$2"; shift ;;
    --branch) [ $# -ge 2 ] || usage_error "--branch needs a name"; BRANCH="$2"; shift ;;
    --allow-protected) ALLOW_PROTECTED=1 ;;
    -*) usage_error "unknown option: $1" ;;
    *)
      if [ -z "$REPO_ARG" ]; then REPO_ARG="$1"
      elif [ -z "$SLUG" ]; then SLUG="$1"
      else usage_error "unexpected argument: $1"
      fi
      ;;
  esac
  shift
done

[ -n "$REPO_ARG" ] && [ -n "$SLUG" ] || usage_error "needs <repo-path> and <slug>"
case "$SLUG" in
  *[!a-z0-9-]*|-*) usage_error "slug must be lowercase letters, digits, and hyphens: $SLUG" ;;
esac
[ -n "$BRANCH" ] || BRANCH="feat/$SLUG"
git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || usage_error "invalid branch name: $BRANCH"

[ -d "$REPO_ARG" ] || die "no such directory: $REPO_ARG"
TOP=$(git -C "$REPO_ARG" rev-parse --show-toplevel 2>/dev/null) || die "not inside a git work tree: $REPO_ARG"
# The first entry of the worktree list is always the main checkout.
MAIN=$(git -C "$TOP" worktree list --porcelain | sed -n '1s/^worktree //p')
[ -n "$MAIN" ] && [ -d "$MAIN" ] || die "cannot find the main checkout of $TOP"

if [ -n "$(git -C "$MAIN" status --porcelain --untracked-files=no)" ]; then
  echo "repo-worktree: note: main checkout has uncommitted changes, left untouched: $MAIN" >&2
fi

WORKTREE="$MAIN/.claude/worktrees/$SLUG"
[ ! -e "$WORKTREE" ] || die "worktree path already exists: $WORKTREE"
if git -C "$MAIN" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  die "branch already exists: $BRANCH"
fi

HAS_ORIGIN=0
git -C "$MAIN" remote get-url origin >/dev/null 2>&1 && HAS_ORIGIN=1

if [ -z "$BASE" ]; then
  [ "$HAS_ORIGIN" -eq 1 ] || die "no origin remote; pass --base <ref>"
  DEFAULT=$(git -C "$MAIN" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  DEFAULT="${DEFAULT#origin/}"
  if [ -z "$DEFAULT" ]; then
    DEFAULT=$(git -C "$MAIN" ls-remote --symref origin HEAD | sed -n 's|^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$|\1|p')
  fi
  [ -n "$DEFAULT" ] || die "cannot find origin's default branch; pass --base <ref>"
  BASE="$DEFAULT"
fi

if [ "$HAS_ORIGIN" -eq 1 ] && git -C "$MAIN" ls-remote --exit-code --heads origin "$BASE" >/dev/null 2>&1; then
  git -C "$MAIN" fetch --quiet origin "refs/heads/$BASE:refs/remotes/origin/$BASE" || die "fetch of origin/$BASE failed"
  START="origin/$BASE"
else
  START="$BASE"
fi
git -C "$MAIN" rev-parse --verify --quiet "$START^{commit}" >/dev/null || die "base is not a commit: $START"

# Mirrors the ~/dev write denies in settings.json and worktree-fill-protected.sh.
PROTECTED_RE='(^|/)\.husky(/|$)|(^|/)\.claude/(settings\.json|settings\.local\.json)$|(^|/)\.claude/(hooks|skills|agents|commands)/'
PROTECTED=""
if [ "$ALLOW_PROTECTED" -eq 0 ]; then
  PROTECTED=$(git -C "$MAIN" ls-tree -r --name-only "$START" | grep -E "$PROTECTED_RE" || true)
fi

if ! git -C "$MAIN" check-ignore -q .claude/worktrees/x; then
  EXCLUDE="$(git -C "$MAIN" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
  mkdir -p "$(dirname "$EXCLUDE")"
  printf '.claude/worktrees/\n' >> "$EXCLUDE"
fi

# --no-track keeps branch.<name>.* out of .git/config, which the sandbox guards.
if [ -z "$PROTECTED" ]; then
  git -C "$MAIN" worktree add --quiet --no-track -b "$BRANCH" "$WORKTREE" "$START" >&2 \
    || die "git worktree add failed for $WORKTREE"
else
  git -C "$MAIN" worktree add --quiet --no-checkout --no-track -b "$BRANCH" "$WORKTREE" "$START" >&2 \
    || die "git worktree add failed for $WORKTREE"
  git -C "$WORKTREE" read-tree HEAD || die "git read-tree failed in $WORKTREE"
  git -C "$WORKTREE" ls-files -z | grep -zvE "$PROTECTED_RE" | git -C "$WORKTREE" checkout-index -z --stdin \
    || die "checkout of the unprotected files failed in $WORKTREE"
  ADMIN=$(git -C "$WORKTREE" rev-parse --path-format=absolute --git-dir)
  FILL="$ADMIN/fill-protected"
  DRIFTED=()
  : > "$FILL"
  while IFS= read -r path; do
    want=$(git -C "$WORKTREE" rev-parse "HEAD:$path")
    if [ -f "$MAIN/$path" ] && [ ! -L "$MAIN/$path" ] \
      && [ "$(git -C "$MAIN" hash-object --no-filters -- "$path")" = "$want" ]; then
      printf '%s\n' "$path" >> "$FILL"
    else
      DRIFTED+=("$path")
    fi
  done <<< "$PROTECTED"
fi

REGISTRY="$HOME/.cache/agent/worktree-repos"
mkdir -p "$(dirname "$REGISTRY")"
touch "$REGISTRY"
grep -Fxq -- "$MAIN" "$REGISTRY" || printf '%s\n' "$MAIN" >> "$REGISTRY"

echo "repo-worktree: created $BRANCH from $START" >&2
if [ -n "$PROTECTED" ]; then
  {
    echo "repo-worktree: the protected files are not checked out yet. Run this next:"
    printf '  ~/.agents/scripts/worktree-fill-protected.sh %q\n' "$WORKTREE"
    if [ ${#DRIFTED[@]} -gt 0 ]; then
      echo "These differ from the main checkout, so the user checks them out with the ! prefix:"
      printf '  ! git -C %q checkout HEAD --' "$WORKTREE"
      printf ' %q' "${DRIFTED[@]}"
      printf '\n'
    fi
  } >&2
  printf '%s\n' "$WORKTREE"
  exit 4
fi
printf '%s\n' "$WORKTREE"
