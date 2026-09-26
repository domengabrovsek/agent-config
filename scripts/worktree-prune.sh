#!/bin/bash
# worktree-prune: identify and (optionally) remove safely-disposable git
# worktrees. Conservative by default - only removes worktrees whose branch
# is upstream-gone (PR merged + remote branch deleted) OR merged into the
# repo's default branch. Locked worktrees are auto-unlocked iff the branch
# is safely removable.
#
# Usage:
#   worktree-prune.sh [--apply] [--repo <path>]
#   worktree-prune.sh audit-all [--apply] [--root <path>]   # default root: $HOME/dev
#
# Without --apply this is dry-run: prints verdicts and exits without changes.
# Exit codes: 0 always (audit/prune are advisory, never block).

set -u

APPLY=0
MODE=prune
REPO=""
ROOT="${HOME}/dev"

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --repo)  REPO="${2:-}"; shift ;;
    --root)  ROOT="${2:-}"; shift ;;
    audit-all) MODE=audit-all ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# Color codes when stdout is a tty
if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_YELLOW=""; C_DIM=""; C_RESET=""
fi

# Determine the repo's default branch (origin/HEAD if set, else main, master, or trunk)
default_branch() {
  local repo="$1"
  local d
  d=$(git -C "$repo" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|^refs/remotes/origin/||')
  if [ -n "$d" ]; then echo "$d"; return; fi
  for cand in main master trunk; do
    git -C "$repo" rev-parse --verify "refs/heads/$cand" >/dev/null 2>&1 && { echo "$cand"; return; }
  done
  echo ""
}

# Parse `git worktree list --porcelain` into rows separated by \037 (unit
# separator): path, HEAD, branch, locked(0|1), prunable(0|1). Not TAB: read
# collapses runs of IFS whitespace, so a detached worktree's empty branch
# would vanish and shift locked into branch.
list_worktrees() {
  local repo="$1"
  git -C "$repo" worktree list --porcelain 2>/dev/null | awk '
    BEGIN        { OFS = "\037" }
    /^worktree / { if (path) print path, head, branch, locked, prunable; path=$2; head=""; branch=""; locked=0; prunable=0; next }
    /^HEAD /     { head=$2; next }
    /^branch /   { sub(/^branch /,""); sub(/^refs\/heads\//,""); branch=$0; next }
    /^locked/    { locked=1; next }
    /^prunable/  { prunable=1; next }
    END          { if (path) print path, head, branch, locked, prunable }
  '
}

is_branch_merged() {
  local repo="$1" branch="$2" default_br="$3"
  [ -z "$default_br" ] && return 1
  git -C "$repo" merge-base --is-ancestor "$branch" "$default_br" 2>/dev/null
}

# A merge commit puts a merged branch's tip on its second-parent side. A tip on
# the default branch's first-parent line means the branch was cut from it and
# has no commits of its own, like a fresh session worktree. A fast-forward
# merge looks the same, so it is kept too.
has_no_own_commits() {
  local repo="$1" tip="$2" default_br="$3"
  git -C "$repo" rev-list --first-parent "$default_br" 2>/dev/null | grep -qxF "$tip"
}

upstream_gone() {
  local repo="$1" branch="$2"
  local track
  track=$(git -C "$repo" for-each-ref --format='%(upstream:track)' "refs/heads/$branch" 2>/dev/null)
  [ "$track" = "[gone]" ]
}

# Verdict per worktree: "safe" or "keep". Echos verdict + reason on stdout.
verdict() {
  local repo="$1" path="$2" head="$3" branch="$4" locked="$5" prunable="$6"
  local default_br
  default_br=$(default_branch "$repo")

  if [ "$prunable" = "1" ]; then
    echo "safe disk-missing-prunable"; return
  fi
  if [ -z "$branch" ]; then
    echo "keep detached-HEAD-no-branch"; return
  fi
  if [ "$branch" = "$default_br" ]; then
    echo "keep default-branch-checkout"; return
  fi
  if upstream_gone "$repo" "$branch"; then
    echo "safe upstream-gone"; return
  fi
  if is_branch_merged "$repo" "$branch" "$default_br"; then
    if has_no_own_commits "$repo" "$head" "$default_br"; then
      echo "keep no-commits-of-its-own"; return
    fi
    echo "safe merged-into-$default_br"; return
  fi
  if [ "$locked" = "1" ]; then
    echo "keep locked-and-not-merged"; return
  fi
  # Unpushed work or open PR
  echo "keep unmerged-or-active"
}

prune_repo() {
  local repo="$1"
  local main_path
  main_path=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)
  [ -z "$main_path" ] && return 0

  # Drop disk-gone entries first
  git -C "$repo" worktree prune 2>/dev/null

  local total=0 safe=0 kept=0 acted=0 failed=0
  local rows
  rows=$(list_worktrees "$repo")
  [ -z "$rows" ] && return 0

  printf '%s== %s ==%s\n' "$C_DIM" "$repo" "$C_RESET"

  while IFS=$'\037' read -r path head branch locked prunable; do
    [ -z "$path" ] && continue
    total=$((total+1))
    # Skip the main worktree
    if [ "$path" = "$main_path" ]; then
      kept=$((kept+1))
      continue
    fi

    local v reason
    v=$(verdict "$repo" "$path" "$head" "$branch" "$locked" "$prunable")
    reason=${v#* }
    v=${v%% *}

    if [ "$v" = "safe" ]; then
      safe=$((safe+1))
      printf '  %sSAFE%s   %s  branch=%s  reason=%s\n' "$C_GREEN" "$C_RESET" "$path" "${branch:-?}" "$reason"
      if [ "$APPLY" = "1" ]; then
        if [ "$locked" = "1" ]; then
          git -C "$repo" worktree unlock "$path" 2>/dev/null
        fi
        local err
        if err=$(git -C "$repo" worktree remove "$path" 2>&1); then
          # Delete the local branch too if not the default and it exists
          if [ -n "$branch" ] && [ "$branch" != "$(default_branch "$repo")" ]; then
            git -C "$repo" branch -D "$branch" >/dev/null 2>&1 || true
          fi
          acted=$((acted+1))
          printf '         %s-> removed%s\n' "$C_DIM" "$C_RESET"
        else
          # remove succeeds when the directory is already gone, so a failure
          # is git refusing, most often over modified or untracked files.
          err=${err%%$'\n'*}
          failed=$((failed+1))
          printf '         %s-> not removed: %s%s\n' "$C_YELLOW" "${err#fatal: }" "$C_RESET"
        fi
      fi
    else
      kept=$((kept+1))
      local color="$C_YELLOW"
      [ "$reason" = "default-branch-checkout" ] && color="$C_DIM"
      printf '  %sKEEP%s   %s  branch=%s  reason=%s\n' "$color" "$C_RESET" "$path" "${branch:-?}" "$reason"
    fi
  done <<< "$rows"

  if [ "$APPLY" = "1" ]; then
    printf '  %s%d total, %d removed, %d kept, %d failed%s\n\n' "$C_DIM" "$total" "$acted" "$kept" "$failed" "$C_RESET"
  else
    printf '  %s%d total, %d safe-to-remove, %d kept%s\n\n' "$C_DIM" "$total" "$safe" "$kept" "$C_RESET"
  fi
}

case "$MODE" in
  prune)
    R="${REPO:-$PWD}"
    git -C "$R" rev-parse --show-toplevel >/dev/null 2>&1 || { echo "not in a git repo: $R" >&2; exit 0; }
    prune_repo "$(git -C "$R" rev-parse --show-toplevel)"
    ;;
  audit-all)
    [ -d "$ROOT" ] || { echo "root not found: $ROOT" >&2; exit 0; }
    # Find repos: any .git directory or file at depth <= 4
    while IFS= read -r git_path; do
      repo=$(dirname "$git_path")
      # Skip nested worktree git dirs (those live inside another repo's tree)
      gd=$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null)
      td=$(git -C "$repo" rev-parse --git-dir 2>/dev/null)
      [ "$gd" != "$td" ] && continue
      prune_repo "$repo"
    done < <(find "$ROOT" -maxdepth 4 \( -name .git -type d -o -name .git -type f \) 2>/dev/null | sort)
    ;;
esac

exit 0
