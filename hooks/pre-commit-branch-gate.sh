#!/bin/bash
# Pre-commit branch gate.
# Blocks `git commit` when HEAD is on main or master.
# PreToolUse hook for Bash(git commit *) and Bash(git -C *). Exit 2 blocks the
# action and feeds the message back to Claude as a tool result.
# Bypass with SKIP_COMMIT_BRANCH_GATE=1 in the environment.

# shellcheck source=lib/resolve-repo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/resolve-repo.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

case "$COMMAND" in
  *"git commit --help"*|*"git commit -h"*) exit 0 ;;
  *"git commit"*|*"git -C "*) ;;
  *) exit 0 ;;
esac

[ "$SKIP_COMMIT_BRANCH_GATE" = "1" ] && exit 0

# `git -C <path> commit` never contains the literal "git commit", so a command
# without either is not ours to gate.
case "$COMMAND" in
  *"git commit"*) ;;
  *) printf '%s\n' "$COMMAND" | grep -q 'git -C  *[^ ]*  *commit' || exit 0 ;;
esac

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
DIR=$(resolve_repo_dir "$COMMAND" "$CWD" commit)
BRANCH=$(git -C "$DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)

# Not in a git repo, or detached HEAD - let it through. Caller handles their own state.
[ -z "$BRANCH" ] && exit 0
[ "$BRANCH" = "HEAD" ] && exit 0

case "$BRANCH" in
  main|master)
    echo "[pre-commit-branch-gate] Refusing to commit directly to '$BRANCH'." >&2
    echo "Create a feature branch first, e.g.:" >&2
    echo "  git checkout -b <type>/<short-description>" >&2
    echo "(Bypass: SKIP_COMMIT_BRANCH_GATE=1)" >&2
    exit 2
    ;;
esac

exit 0
