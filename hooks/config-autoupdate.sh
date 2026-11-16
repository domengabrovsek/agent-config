#!/bin/bash
# SessionStart hook (matcher: startup).
# Fast-forwards the agent config checkout to its remote default branch, so a
# merged pull request goes live on the next session without a manual pull.
# Non-blocking: it always exits 0.
#
# The sandbox keeps the live checkout read-only to agent commands, so a pull
# from inside a session fails halfway. Hooks run outside the sandbox, which
# makes this hook the one place that can update the checkout. It only
# fast-forwards, and only a clean checkout on the default branch, so it never
# touches local work. Untracked files do not count as local work. A clean
# checkout left on a branch that is gone from the remote, as after a merge,
# first switches back to the default branch.
#
# The checkout resolves through config_repo_dir in hooks/lib/config-repo.sh.
#
# Bypass with SKIP_CONFIG_AUTOUPDATE=1 in the environment.

[ "$SKIP_CONFIG_AUTOUPDATE" = "1" ] && exit 0

# shellcheck source=lib/config-repo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/config-repo.sh"

LIVE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
REPO=$(config_repo_dir "$LIVE_DIR") || exit 0
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || exit 0

say() { echo "[config-autoupdate] $1"; }

DEFAULT=$(git -C "$REPO" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
DEFAULT=${DEFAULT#origin/}
DEFAULT=${DEFAULT:-main}

# A slow network or a credential prompt must not hold up the session start.
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=5}"
if ! GIT_TERMINAL_PROMPT=0 git -C "$REPO" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=5 \
  fetch --quiet origin "$DEFAULT" 2>/dev/null; then
  exit 0
fi

CLEAN=1
[ -z "$(git -C "$REPO" status --porcelain --untracked-files=no)" ] || CLEAN=0

# A branch that was pushed and is now gone from the remote was merged or
# dropped, so a clean checkout returns to the default branch. The branch and
# its commits stay; only the checkout moves.
BRANCH=$(git -C "$REPO" branch --show-current)
if [ -n "$BRANCH" ] && [ "$BRANCH" != "$DEFAULT" ] && [ "$CLEAN" -eq 1 ] \
  && git -C "$REPO" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  GIT_TERMINAL_PROMPT=0 git -C "$REPO" ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1
  if [ $? -eq 2 ] && git -C "$REPO" switch --quiet "$DEFAULT" 2>/dev/null; then
    say "Switched agent config from $BRANCH, which is gone from origin, back to $DEFAULT."
    BRANCH=$DEFAULT
  fi
fi

BEHIND=$(git -C "$REPO" rev-list --count "HEAD..origin/$DEFAULT" 2>/dev/null)
[ "${BEHIND:-0}" -gt 0 ] || exit 0

if [ "$BRANCH" != "$DEFAULT" ]; then
  say "Agent config in $REPO is on ${BRANCH:-a detached HEAD}, so $BEHIND merged commits on $DEFAULT are not live. Make config changes in a worktree."
  exit 0
fi
if [ "$CLEAN" -eq 0 ]; then
  say "Agent config in $REPO has local changes, so $BEHIND merged commits are not live."
  exit 0
fi

if git -C "$REPO" merge --ff-only --quiet "origin/$DEFAULT" >/dev/null 2>&1; then
  say "Updated agent config to $(git -C "$REPO" log -1 --format='%h %s')."
else
  say "Agent config in $REPO could not fast-forward to origin/$DEFAULT."
fi
exit 0
