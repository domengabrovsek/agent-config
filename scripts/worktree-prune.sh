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

# Determine the repo's default branch (origin/HEAD if set, else main, else master)
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

# Parse `git worktree list --porcelain` into TAB-separated rows:
#   path \t HEAD \t branch \t locked(0|1) \t prunable(0|1)
list_worktrees() {
  local repo="$1"
  git -C "$repo" worktree list --porcelain 2>/dev/null | awk '
    /^worktree / { if (path) print path"\t"head"\t"branch"\t"locked"\t"prunable; path=$2; head=""; branch=""; locked=0; prunable=0; next }
    /^HEAD /     { head=$2; next }
    /^branch /   { sub(/^branch /,""); sub(/^refs\/heads\//,""); branch=$0; next }
    /^locked/    { locked=1; next }
    /^prunable/  { prunable=1; next }
    END          { if (path) print path"\t"head"\t"branch"\t"locked"\t"prunable }
  '
}

is_branch_merged() {
  local repo="$1" branch="$2" default_br="$3"
  [ -z "$default_br" ] && return 1
  git -C "$repo" merge-base --is-ancestor "$branch" "$default_br" 2>/dev/null
}

upstream_gone() {
  local repo="$1" branch="$2"
  local track
  track=$(git -C "$repo" for-each-ref --format='%(upstream:track)' "refs/heads/$branch" 2>/dev/null)
  [ "$track" = "[gone]" ]
}

# Verdict per worktree: "safe" or "keep". Echos verdict + reason on stdout.
verdict() {
  local repo="$1" path="$2" branch="$3" locked="$4" prunable="$5"
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

  local total=0 safe=0 kept=0 acted=0
  local rows
  rows=$(list_worktrees "$repo")
  [ -z "$rows" ] && return 0

  printf '%s== %s ==%s\n' "$C_DIM" "$repo" "$C_RESET"

  # shellcheck disable=SC2034  # head is a positional field, read but unused
  while IFS=$'\t' read -r path head branch locked prunable; do
    [ -z "$path" ] && continue
    total=$((total+1))
    # Skip the main worktree
    if [ "$path" = "$main_path" ]; then
      kept=$((kept+1))
      continue
    fi

    local v reason
    v=$(verdict "$repo" "$path" "$branch" "$locked" "$prunable")
    reason=${v#* }
    v=${v%% *}

    if [ "$v" = "safe" ]; then
      safe=$((safe+1))
      printf '  %sSAFE%s   %s  branch=%s  reason=%s\n' "$C_GREEN" "$C_RESET" "$path" "${branch:-?}" "$reason"
      if [ "$APPLY" = "1" ]; then
        if [ "$locked" = "1" ]; then
          git -C "$repo" worktree unlock "$path" 2>/dev/null
        fi
        if git -C "$repo" worktree remove "$path" 2>/dev/null; then
          # Delete the local branch too if not the default and it exists
          if [ -n "$branch" ] && [ "$branch" != "$(default_branch "$repo")" ]; then
            git -C "$repo" branch -D "$branch" >/dev/null 2>&1 || true
          fi
          acted=$((acted+1))
          printf '         %s-> removed%s\n' "$C_DIM" "$C_RESET"
        else
          # Disk-missing, just clean the registry
          git -C "$repo" worktree prune 2>/dev/null
          acted=$((acted+1))
          printf '         %s-> pruned (disk gone)%s\n' "$C_DIM" "$C_RESET"
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
    printf '  %s%d total, %d removed, %d kept%s\n\n' "$C_DIM" "$total" "$acted" "$kept" "$C_RESET"
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
