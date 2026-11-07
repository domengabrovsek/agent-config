#!/bin/bash
# Pre-commit Co-Authored-By gate.
# PreToolUse hook on Bash(git commit *) and Bash(git -C *). Blocks the commit
# when the command string contains a Co-Authored-By trailer in any case. Per
# rules/git-conventions.md: never add Co-Authored-By or any AI attribution.
# Exit 2 blocks the action and feeds the message back to Claude.
# Bypass with SKIP_COAUTHOR_GATE=1.

# shellcheck source=lib/resolve-repo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/resolve-repo.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

git_runs "$COMMAND" commit || exit 0
git_args_ask_help && exit 0

[ "$SKIP_COAUTHOR_GATE" = "1" ] && exit 0

# The whole command is searched, so a trailer in -m, a heredoc, or a -F path
# all count.
if echo "$COMMAND" | grep -qiE '\bco-authored-by:'; then
  echo "[pre-commit-coauthor-gate] Refusing to commit with Co-Authored-By trailer." >&2
  echo "Per rules/git-conventions.md, never add Co-Authored-By or any AI attribution to commits." >&2
  echo "Remove the trailer from the commit message and re-run." >&2
  echo "(Bypass: SKIP_COAUTHOR_GATE=1)" >&2
  exit 2
fi

exit 0
