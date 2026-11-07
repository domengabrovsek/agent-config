#!/bin/bash
# Shared .claude/state/ lookup for the test lock and the evidence gate.
#
# .claude/state/ is untracked and per checkout. The main checkout is searched
# first, so a worktree's own copy of a file (an empty tests.lock, say) cannot
# shadow the main checkout's. The worktree is searched only for files the main
# checkout lacks.

# state_roots <toplevel>
# Sets ROOTS to the main checkout, then <toplevel> when it is a worktree.
state_roots() {
  local common main
  ROOTS=("$1")
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  [ -n "$common" ] || return 0
  main=$(dirname "$common")
  if [ "$main" != "$1" ] && [ -d "$main" ]; then
    ROOTS=("$main" "$1")
  fi
}

# run_file <branch> <name>
# Prints the first ROOTS entry's .claude/state/runs/<branch-slug>/<name> that
# exists. Fails when none does.
run_file() {
  local root
  for root in "${ROOTS[@]}"; do
    if [ -f "$root/.claude/state/runs/${1//\//-}/$2" ]; then
      printf '%s\n' "$root/.claude/state/runs/${1//\//-}/$2"
      return 0
    fi
  done
  return 1
}
