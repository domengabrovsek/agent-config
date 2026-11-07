#!/bin/bash
# Shared .claude/state/ lookup for the test lock and the evidence gate.
#
# .claude/state/ is untracked and per checkout, so a worktree looks in its own
# tree first and then in the main checkout.

# state_roots <toplevel>
# Sets ROOTS to <toplevel>, then the main checkout when <toplevel> is a worktree.
state_roots() {
  local common
  ROOTS=("$1")
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  if [ -n "$common" ] && [ "$(dirname "$common")" != "$1" ]; then
    ROOTS+=("$(dirname "$common")")
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
