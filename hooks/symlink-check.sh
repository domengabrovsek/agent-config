#!/bin/bash
# SessionStart hook (matcher: startup).
# Warns to stderr when this Claude config dir has drifted from the checkout.
# Non-blocking.
#
# scripts/setup-hosts.sh is the single drift oracle. This hook invokes its
# --check mode and translates the result, the same way the pi drift-check
# extension does; a second copy of the link manifest here would silently
# diverge from the one the bootstrap actually creates.
#
# The dir checked resolves from $CLAUDE_CONFIG_DIR (default ~/.claude), so a
# second account's dir is audited by its own sessions instead of being skipped.
#
# Bypass with SKIP_SYMLINK_CHECK=1 in the environment.

[ "$SKIP_SYMLINK_CHECK" = "1" ] && exit 0

LIVE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
[ -d "$LIVE_DIR" ] || exit 0

# Without an override, audit the checkout this dir's hooks link points into,
# read as the bootstrap wrote it. The hook's own path would name a second
# clone whenever a session runs the copy under CLAUDE_PROJECT_DIR.
REPO="${AGENT_CONFIG_REPO:-$CLAUDE_DOTFILES_REPO}"
if [ -z "$REPO" ]; then
  HOOKS_LINK=$(readlink "$LIVE_DIR/hooks" 2>/dev/null)
  case "$HOOKS_LINK" in
    /*) [ -f "${HOOKS_LINK%/hooks}/scripts/setup-hosts.sh" ] && REPO="${HOOKS_LINK%/hooks}" ;;
  esac
  REPO="${REPO:-$HOME/dev/personal/agent-config}"
fi
[ -d "$REPO" ] || exit 0

SETUP="$REPO/scripts/setup-hosts.sh"
[ -f "$SETUP" ] || exit 0

# Scope the oracle to this one dir and this one host. An explicit --host wins
# over a HARNESS_SKIP_HOSTS entry in the machine scope file, which is what we
# want: a session running from this dir always audits the dir it runs from.
if OUTPUT=$(CLAUDE_CONFIG_DIRS="$LIVE_DIR" AGENT_CONFIG_REPO="$REPO" \
  bash "$SETUP" --check --host claude 2>/dev/null); then
  exit 0
fi

# Same failure states the pi drift-check extension recognises.
ISSUES=$(printf '%s\n' "$OUTPUT" | grep -E '[[:space:]](MISSING|MISSING-SRC|CONFLICT|WRONG-LINK|REFUSED|FAILED)[[:space:]]')

[ -z "$ISSUES" ] && exit 0

echo "[symlink-check] $LIVE_DIR has drifted from $REPO:" >&2
printf '%s\n' "$ISSUES" | sed 's/^/  - /' >&2
echo "" >&2
echo "Converge with:" >&2
echo "  bash $SETUP --apply --host claude" >&2
echo "  (add --adopt to move a conflicting real path to a timestamped backup)" >&2
echo "" >&2
echo "(Override repo location: AGENT_CONFIG_REPO=/path/to/repo. Override config dir: CLAUDE_CONFIG_DIR=/path/to/dir. Bypass this check: SKIP_SYMLINK_CHECK=1.)" >&2

exit 0
