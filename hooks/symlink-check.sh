#!/bin/bash
# SessionStart hook (matcher: startup).
# Warns to stderr when the expected symlinks from the live config dir to the
# dotfiles repo are missing, replaced by a real file, or pointing to the wrong
# target. Non-blocking.
#
# The dir checked resolves from $CLAUDE_CONFIG_DIR (default ~/.claude), the same
# way scripts/setup-symlinks.sh picks its target, so a second account's dir is
# audited by its own sessions instead of being skipped.
#
# Bypass with SKIP_SYMLINK_CHECK=1 in the environment.

[ "$SKIP_SYMLINK_CHECK" = "1" ] && exit 0

REPO="${AGENT_CONFIG_REPO:-${CLAUDE_DOTFILES_REPO:-$HOME/dev/personal/agent-config}}"
[ -d "$REPO" ] || exit 0

LIVE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
[ -d "$LIVE_DIR" ] || exit 0

EXPECTED=(
  "CLAUDE.md|$REPO/CLAUDE.md"
  "settings.json|$REPO/settings.json"
  "agents|$REPO/agents"
  "hooks|$REPO/hooks"
  "rules|$REPO/rules"
  "skills|$REPO/skills"
  "scripts|$REPO/scripts"
  "statusline.sh|$REPO/scripts/statusline.sh"
  "pull_request_template.md|$REPO/.github/pull_request_template.md"
)

ISSUES=()
for ENTRY in "${EXPECTED[@]}"; do
  NAME="${ENTRY%%|*}"
  WANT="${ENTRY##*|}"
  LIVE="$LIVE_DIR/$NAME"

  if [ ! -e "$LIVE" ] && [ ! -L "$LIVE" ]; then
    ISSUES+=("MISSING:       $LIVE  (expected -> $WANT)")
  elif [ ! -L "$LIVE" ]; then
    ISSUES+=("NOT-A-SYMLINK: $LIVE  is a real file (expected -> $WANT)")
  else
    GOT=$(readlink "$LIVE")
    if [ "$GOT" != "$WANT" ]; then
      ISSUES+=("WRONG-TARGET:  $LIVE -> $GOT  (expected -> $WANT)")
    fi
  fi
done

if [ ${#ISSUES[@]} -gt 0 ]; then
  echo "[symlink-check] $LIVE_DIR symlinks have drifted from $REPO:" >&2
  for ISSUE in "${ISSUES[@]}"; do echo "  - $ISSUE" >&2; done
  echo "" >&2
  echo "Fix each path with:" >&2
  echo "  unlink <path> 2>/dev/null; rm -rf <path> 2>/dev/null; ln -s <expected-target> <path>" >&2
  echo "" >&2
  echo "(Override repo location: CLAUDE_DOTFILES_REPO=/path/to/repo. Override config dir: CLAUDE_CONFIG_DIR=/path/to/dir. Bypass this check: SKIP_SYMLINK_CHECK=1.)" >&2
fi

exit 0
