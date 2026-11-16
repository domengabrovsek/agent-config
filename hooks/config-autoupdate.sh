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
# touches local work. Untracked files do not count as local work.
#
# The checkout resolves like symlink-check.sh: AGENT_CONFIG_REPO, else the
# target of this config dir's hooks link.
#
# Bypass with SKIP_CONFIG_AUTOUPDATE=1 in the environment.

[ "$SKIP_CONFIG_AUTOUPDATE" = "1" ] && exit 0

LIVE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
REPO="${AGENT_CONFIG_REPO:-}"
if [ -z "$REPO" ]; then
  HOOKS_LINK=$(readlink "$LIVE_DIR/hooks" 2>/dev/null)
  case "$HOOKS_LINK" in
    /*) REPO="${HOOKS_LINK%/hooks}" ;;
  esac
fi
[ -n "$REPO" ] && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || exit 0

say() { echo "[config-autoupdate] $1"; }

DEFAULT=$(git -C "$REPO" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
DEFAULT=${DEFAULT#origin/}
DEFAULT=${DEFAULT:-main}

# A slow network must not hold up the session start.
if ! GIT_TERMINAL_PROMPT=0 git -C "$REPO" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=5 \
  fetch --quiet origin "$DEFAULT" 2>/dev/null; then
  exit 0
fi

BEHIND=$(git -C "$REPO" rev-list --count "HEAD..origin/$DEFAULT" 2>/dev/null)
[ "${BEHIND:-0}" -gt 0 ] || exit 0

BRANCH=$(git -C "$REPO" branch --show-current)
if [ "$BRANCH" != "$DEFAULT" ]; then
  say "Agent config in $REPO is on $BRANCH, so $BEHIND merged commits on $DEFAULT are not live. Make config changes in a worktree."
  exit 0
fi
if [ -n "$(git -C "$REPO" status --porcelain --untracked-files=no)" ]; then
  say "Agent config in $REPO has local changes, so $BEHIND merged commits are not live."
  exit 0
fi

if git -C "$REPO" merge --ff-only --quiet "origin/$DEFAULT" >/dev/null 2>&1; then
  say "Updated agent config to $(git -C "$REPO" log -1 --format='%h %s')."
else
  say "Agent config in $REPO could not fast-forward to origin/$DEFAULT."
fi
exit 0
