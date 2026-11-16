#!/bin/bash
# worktree-prune: identify and (optionally) remove safely-disposable git
# worktrees. Conservative by default - only removes worktrees whose branch
# is merged into the repo's default branch, squash-merged (its changes are
# already in the default branch even though its tip is not an ancestor), or
# upstream-gone with every commit still reachable from the default branch or
# a remote. A lock marks a worktree in use, so locked worktrees are kept
# unless --force-locked is passed.
#
# Usage:
#   worktree-prune.sh [--apply] [--force-locked] [--min-idle <min>] [--repo <path>]
#   worktree-prune.sh audit-all [--apply] [--force-locked] [--min-idle <min>] [--root <path>]
#   worktree-prune.sh --registry [<file>] [--apply] [--force-locked] [--min-idle <min>]
#
# Without --apply this is dry-run: prints verdicts and exits without changes.
# --registry prunes each repo listed in <file>, one absolute path per line,
# default ~/.cache/agent/worktree-repos. With --apply it also drops entries
# that are gone or no longer a repo root, rewriting the file atomically.
# --min-idle keeps worktrees whose index or HEAD changed in the last <min>
# minutes. Exit codes: 0 always (audit/prune are advisory, never block).

set -u

APPLY=0
FORCE_LOCKED=0
MIN_IDLE=0
MODE=prune
REPO=""
ROOT="${HOME}/dev"
REGISTRY="${HOME}/.cache/agent/worktree-repos"

set_mode() {
  if [ "$MODE" != prune ] && [ "$MODE" != "$1" ]; then
    echo "audit-all and --registry cannot be combined" >&2; exit 2
  fi
  MODE="$1"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --force-locked) FORCE_LOCKED=1 ;;
    --min-idle)
      MIN_IDLE="${2:-}"; shift
      case "$MIN_IDLE" in ''|*[!0-9]*) echo "--min-idle needs whole minutes" >&2; exit 2 ;; esac
      ;;
    --repo)  REPO="${2:-}"; shift ;;
    --root)  ROOT="${2:-}"; shift ;;
    audit-all) set_mode audit-all ;;
    --registry)
      set_mode registry
      case "${2:-}" in ''|-*|audit-all) ;; *) REGISTRY="$2"; shift ;; esac
      ;;
    -h|--help)
      sed -n '2,/^[^#]/s/^# \{0,1\}//p' "$0"
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

# The worktree this run starts in, whichever repo is being pruned: a registry
# or audit-all pass must not remove the tree its own session stands in.
START_TOP=$(git rev-parse --show-toplevel 2>/dev/null)

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
# separator): path, HEAD, branch, locked(0|1), prunable(0|1), lock reason. Not
# TAB: read collapses runs of IFS whitespace, so a detached worktree's empty
# branch would vanish and shift locked into branch. The path is everything
# after "worktree ", since it may hold spaces. The lock reason stays as git
# prints it, C-quoted when it holds control bytes, so a row stays one line.
list_worktrees() {
  local repo="$1"
  git -C "$repo" worktree list --porcelain 2>/dev/null | awk '
    BEGIN        { OFS = "\037" }
    /^worktree / { if (path) print path, head, branch, locked, prunable, lock; path=substr($0, 10); head=""; branch=""; locked=0; prunable=0; lock=""; next }
    /^HEAD /     { head=$2; next }
    /^branch /   { sub(/^branch /,""); sub(/^refs\/heads\//,""); branch=$0; next }
    /^locked/    { locked=1; lock=substr($0, 8); next }
    /^prunable/  { prunable=1; next }
    END          { if (path) print path, head, branch, locked, prunable, lock }
  '
}

# Undo git's C-style quoting of a porcelain field. Git wraps the field in
# double quotes only when it holds a quote, backslash, control byte, or
# non-ASCII byte, and escapes those as \" \\ \t \n or 3-digit octal, all of
# which printf %b decodes except \".
unquote_c() {
  local s="$1"
  case "$s" in
    \"*\")
      s=${s#\"}; s=${s%\"}
      s=${s//\\\"/\"}
      printf '%b' "$s"
      ;;
    *) printf '%s' "$s" ;;
  esac
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

has_branch() {
  git -C "$1" show-ref --verify --quiet "refs/heads/$2"
}

# A squash merge rewrites the branch as one commit on the default branch, so
# the tip is not an ancestor. Merge the branch into default in memory instead:
# when the result equals default, the branch adds nothing and is safe to drop.
# Needs git >= 2.38; older git rejects the flag and the tree is kept.
is_branch_squash_merged() {
  local repo="$1" branch="$2" default_br="$3"
  [ -z "$default_br" ] && return 1
  local out tree
  out=$(git -C "$repo" merge-tree --write-tree "$default_br" "$branch" 2>/dev/null) || return 1
  tree=${out%%$'\n'*}
  [ -n "$tree" ] || return 1
  git -C "$repo" diff --quiet "$default_br" "$tree" 2>/dev/null
}

upstream_gone() {
  local repo="$1" branch="$2"
  local track
  track=$(git -C "$repo" for-each-ref --format='%(upstream:track)' "refs/heads/$branch" 2>/dev/null)
  [ "$track" = "[gone]" ]
}

# A gone upstream says only that the remote branch was deleted, not that its
# commits landed anywhere. The branch holds no unique work only when every
# commit is reachable from the default branch or some remote-tracking ref.
all_commits_shared() {
  local repo="$1" branch="$2" default_br="$3" out
  out=$(git -C "$repo" rev-list -n 1 "refs/heads/$branch" --not ${default_br:+"refs/heads/$default_br"} --remotes 2>/dev/null) || return 1
  [ -z "$out" ]
}

# The gate for deleting a branch: its commits live elsewhere, or its changes
# already sit in the default branch as a squash.
branch_disposable() {
  all_commits_shared "$@" || is_branch_squash_merged "$@"
}

# Index and HEAD under the worktree's git dir change on every commit, checkout,
# and stage, so a recent mtime means a session is likely still working there.
recently_active() {
  local path="$1" gitdir
  [ "$MIN_IDLE" -gt 0 ] && [ -d "$path" ] || return 1
  gitdir=$(git -C "$path" rev-parse --path-format=absolute --git-dir 2>/dev/null) || return 1
  [ -n "$(find "$gitdir" -maxdepth 1 \( -name index -o -name HEAD \) -mmin "-$MIN_IDLE" 2>/dev/null)" ]
}

# Verdict per worktree: "safe" or "keep". Echos verdict + reason on stdout.
verdict() {
  local repo="$1" path="$2" head="$3" branch="$4" locked="$5" prunable="$6" default_br="$7"

  if [ "$locked" = "1" ] && [ "$FORCE_LOCKED" != "1" ]; then
    echo "keep locked"; return
  fi
  if recently_active "$path"; then
    echo "keep active-in-last-${MIN_IDLE}m"; return
  fi
  if [ "$prunable" = "1" ]; then
    echo "safe disk-missing-prunable"; return
  fi
  if [ -z "$branch" ]; then
    echo "keep detached-HEAD-no-branch"; return
  fi
  if [ "$branch" = "$default_br" ]; then
    echo "keep default-branch-checkout"; return
  fi
  if upstream_gone "$repo" "$branch" && all_commits_shared "$repo" "$branch" "$default_br"; then
    echo "safe upstream-gone"; return
  fi
  if is_branch_merged "$repo" "$branch" "$default_br"; then
    if has_no_own_commits "$repo" "$head" "$default_br"; then
      echo "keep no-commits-of-its-own"; return
    fi
    echo "safe merged-into-$default_br"; return
  fi
  if is_branch_squash_merged "$repo" "$branch" "$default_br"; then
    echo "safe squash-merged-into-$default_br"; return
  fi
  if upstream_gone "$repo" "$branch"; then
    echo "keep upstream-gone-with-unpushed-commits"; return
  fi
  # Unpushed work or open PR
  echo "keep unmerged-or-active"
}

# Ignored files under .claude/state/ hold plans, specs, and run files that
# `git worktree remove` would delete. Copy each into the main checkout before
# removal. A file the main checkout already holds with other content blocks
# removal instead, so neither copy is lost. Sets STATE_CONFLICT on refusal.
preserve_state() {
  local wt="$1" main="$2" rel
  local -a files=()
  STATE_CONFLICT=""
  COPIED=()
  [ -d "$wt/.claude/state" ] || return 0
  # runs/ holds per-branch run files for the branch being deleted; a copy in
  # main would outrank a later worktree that reuses the branch name.
  while IFS= read -r -d '' rel; do
    case "$rel" in .claude/state/runs/*) continue ;; esac
    files+=("$rel")
  done < <(git -C "$wt" ls-files -z --others --ignored --exclude-standard -- .claude/state 2>/dev/null)
  [ "${#files[@]}" -gt 0 ] || return 0
  if [ -z "$main" ]; then
    STATE_CONFLICT=".claude/state has files and the repo has no main checkout to keep them"; return 1
  fi
  for rel in "${files[@]}"; do
    if [ -e "$main/$rel" ] && ! cmp -s "$wt/$rel" "$main/$rel"; then
      STATE_CONFLICT="$rel differs from the main checkout"; return 1
    fi
  done
  for rel in "${files[@]}"; do
    [ -e "$main/$rel" ] && continue
    if ! { mkdir -p "$(dirname "$main/$rel")" && cp -p "$wt/$rel" "$main/$rel"; }; then
      [ "${#COPIED[@]}" -gt 0 ] && rm -f "${COPIED[@]}"
      STATE_CONFLICT="$rel could not be copied to the main checkout"; return 1
    fi
    COPIED+=("$main/$rel")
  done
}

# delete_branch <repo> <branch> <default>: `git branch -d` when git can see the
# merge, else -D only after branch_disposable confirms nothing is lost.
delete_branch() {
  local repo="$1" branch="$2" default_br="$3"
  git -C "$repo" branch -d "$branch" >/dev/null 2>&1 && return 0
  branch_disposable "$repo" "$branch" "$default_br" || return 1
  git -C "$repo" branch -D "$branch" >/dev/null 2>&1
}

# take_lock <dir>: mkdir is atomic, so one --apply pass at a time holds <dir>.
# Two passes on one repo can both copy a worktree's state, and the one whose
# removal fails then deletes the copy the other just kept. A sandboxed pass
# cannot see other processes, so kill -0 alone would call a live owner dead.
# A pass takes seconds per repo and the hook's cwd pass is capped at 30s.
LOCK_STALE_MIN=10
take_lock() {
  local dir="$1" pid
  if ! mkdir "$dir" 2>/dev/null; then
    [ -n "$(find "$dir" -maxdepth 0 -mmin +"$LOCK_STALE_MIN" 2>/dev/null)" ] || return 1
    pid=$(cat "$dir/pid" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && return 1
    rm -rf "$dir"
    mkdir "$dir" 2>/dev/null || return 1
  fi
  HELD_LOCK="$dir"
  echo "$$" > "$dir/pid"
}

release_lock() {
  [ -n "$HELD_LOCK" ] && rm -rf "$HELD_LOCK"
  HELD_LOCK=""
}

HELD_LOCK=""
trap release_lock EXIT
trap 'exit 1' HUP INT TERM

prune_repo() {
  local repo="$1" common
  if [ "$APPLY" != "1" ]; then
    prune_repo_unlocked "$repo"; return 0
  fi
  common=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  if ! take_lock "$common/worktree-prune.lock"; then
    printf '%s== %s ==%s\n  %sSKIP%s   another prune pass holds this repo\n\n' "$C_DIM" "$repo" "$C_RESET" "$C_YELLOW" "$C_RESET"
    return 0
  fi
  prune_repo_unlocked "$repo"
  release_lock
}

prune_repo_unlocked() {
  local repo="$1"
  local current main_path="" common
  current=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)
  [ -z "$current" ] && return 0
  # The main checkout owns the common .git dir; a bare repo has no checkout.
  common=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  [ "$(basename "$common")" = .git ] && main_path=$(dirname "$common")

  # Drop disk-gone entries first
  git -C "$repo" worktree prune 2>/dev/null

  local total=0 safe=0 kept=0 acted=0 failed=0
  local rows
  rows=$(list_worktrees "$repo")
  [ -z "$rows" ] && return 0

  printf '%s== %s ==%s\n' "$C_DIM" "$repo" "$C_RESET"
  local default_br
  default_br=$(default_branch "$repo")

  while IFS=$'\037' read -r path head branch locked prunable lock_reason; do
    [ -z "$path" ] && continue
    total=$((total+1))
    # Skip the main checkout and the worktree this run started in
    if [ "$path" = "$main_path" ] || [ "$path" = "$current" ] || [ "$path" = "$START_TOP" ]; then
      kept=$((kept+1))
      continue
    fi

    local v reason
    v=$(verdict "$repo" "$path" "$head" "$branch" "$locked" "$prunable" "$default_br")
    reason=${v#* }
    v=${v%% *}

    if [ "$v" = "safe" ]; then
      safe=$((safe+1))
      printf '  %sSAFE%s   %s  branch=%s  reason=%s\n' "$C_GREEN" "$C_RESET" "$path" "${branch:-?}" "$reason"
      if [ "$APPLY" = "1" ]; then
        local unlocked=0 err
        if ! preserve_state "$path" "$main_path"; then
          failed=$((failed+1))
          printf '         %s-> not removed: %s%s\n' "$C_YELLOW" "$STATE_CONFLICT" "$C_RESET"
          continue
        fi
        if [ "$locked" = "1" ] && git -C "$repo" worktree unlock "$path" 2>/dev/null; then
          unlocked=1
        fi
        if err=$(git -C "$repo" worktree remove "$path" 2>&1); then
          acted=$((acted+1))
          printf '         %s-> removed%s\n' "$C_DIM" "$C_RESET"
          if [ -n "$branch" ] && [ "$branch" != "$default_br" ] && has_branch "$repo" "$branch" \
            && ! delete_branch "$repo" "$branch" "$default_br"; then
            printf '         %s-> branch %s kept: it has commits found nowhere else%s\n' "$C_YELLOW" "$branch" "$C_RESET"
          fi
        else
          # remove succeeds when the directory is already gone, so a failure
          # is git refusing, most often over modified or untracked files.
          err=${err%%$'\n'*}
          failed=$((failed+1))
          # The worktree stays, so its state stays authoritative there.
          [ "${#COPIED[@]}" -gt 0 ] && rm -f "${COPIED[@]}"
          printf '         %s-> not removed: %s%s\n' "$C_YELLOW" "${err#fatal: }" "$C_RESET"
          # The tree stays on disk, so it keeps the lock its host set.
          if [ "$unlocked" = "1" ] && ! err=$(git -C "$repo" worktree lock --reason "$(unquote_c "$lock_reason")" "$path" 2>&1); then
            err=${err%%$'\n'*}
            printf '         %s-> left unlocked: %s%s\n' "$C_YELLOW" "${err#fatal: }" "$C_RESET"
          fi
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

# in_list <list> <line>: <line> appears whole in the newline-ended <list>.
in_list() {
  case $'\n'"$1" in *$'\n'"$2"$'\n'*) return 0 ;; esac
  return 1
}

# A live entry is an absolute path that is its own repo's top level. A plain
# rev-parse would also accept a deleted repo's leftover directory inside some
# other repo, and then prune that one.
registry_entry_live() {
  local entry="$1" top real
  case "$entry" in /*) ;; *) return 1 ;; esac
  [ -d "$entry" ] || return 1
  top=$(git -C "$entry" rev-parse --show-toplevel 2>/dev/null) || return 1
  real=$(cd "$entry" 2>/dev/null && pwd -P) || return 1
  [ "$top" = "$real" ]
}

# compact_registry <file> <stale-list>: rewrite <file> without stale entries,
# blanks, or repeats. It re-reads the file at write time, so a line another
# session appended during the prune survives; tmp file plus mv keeps readers
# from seeing a half-written file.
compact_registry() {
  local reg="$1" stale="$2" tmp line kept=""
  tmp=$(mktemp "$reg.XXXXXX" 2>/dev/null) || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    in_list "$stale" "$line" && continue
    in_list "$kept" "$line" && continue
    kept="$kept$line"$'\n'
    printf '%s\n' "$line"
  done < "$reg" > "$tmp"
  mv -f "$tmp" "$reg" 2>/dev/null || rm -f "$tmp"
}

prune_registry() {
  local reg="$1" entry seen="" stale="" dirty=0
  if [ ! -s "$reg" ]; then
    printf '%sregistry empty or missing: %s%s\n' "$C_DIM" "$reg" "$C_RESET"
    return 0
  fi
  while IFS= read -r entry || [ -n "$entry" ]; do
    if [ -z "$entry" ] || in_list "$seen" "$entry"; then
      dirty=1; continue
    fi
    seen="$seen$entry"$'\n'
    if registry_entry_live "$entry"; then
      prune_repo "$entry"
      continue
    fi
    dirty=1
    stale="$stale$entry"$'\n'
    printf '%s== %s ==%s\n' "$C_DIM" "$entry" "$C_RESET"
    if [ "$APPLY" = "1" ]; then
      printf '  %sSTALE%s  not a repo root, dropped from the registry\n\n' "$C_YELLOW" "$C_RESET"
    else
      printf '  %sSTALE%s  not a repo root, --apply drops it from the registry\n\n' "$C_YELLOW" "$C_RESET"
    fi
  done < "$reg"
  if [ "$APPLY" = "1" ] && [ "$dirty" = "1" ] && take_lock "$reg.lock"; then
    compact_registry "$reg" "$stale"
    release_lock
  fi
  return 0
}

case "$MODE" in
  registry)
    prune_registry "$REGISTRY"
    ;;
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
