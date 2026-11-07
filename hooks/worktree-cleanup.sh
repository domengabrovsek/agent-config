#!/bin/bash
# SessionEnd hook: opportunistically prune safely-disposable worktrees in
# the current repo. Conservative - only removes worktrees whose branch is
# merged into default, squash-merged, or upstream-gone with nothing unpushed.
# Locked worktrees and any touched in the last 30 minutes stay, because other
# live sessions may be using them. Always exits 0; never blocks.
# Disable per-session with CLAUDE_DISABLE_WORKTREE_CLEANUP=1.

set -u

if [ "${CLAUDE_DISABLE_WORKTREE_CLEANUP:-0}" = "1" ]; then
  exit 0
fi

# The prune script comes from this hook's own checkout, never the opened
# project, so a repo cannot ship a scripts/worktree-prune.sh that runs here.
SELF=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null) || exit 0
SCRIPT="$(dirname "$(dirname "$SELF")")/scripts/worktree-prune.sh"
[ -x "$SCRIPT" ] || exit 0

git -C "$PWD" rev-parse --show-toplevel >/dev/null 2>&1 || exit 0

"$SCRIPT" --apply --min-idle 30 --repo "$PWD" >/dev/null 2>&1 || true
exit 0
