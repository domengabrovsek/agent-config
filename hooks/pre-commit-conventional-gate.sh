#!/bin/bash
# Pre-commit conventional-commit format gate.
# PreToolUse hook on Bash(git commit *). Extracts the subject line from the
# commit command and checks it against the conventional-commits regex from
# rules/git-conventions.md.
#
# Skips amend / fixup / squash / no-edit (auto-generated messages or reusing
# existing) and Merge / Revert subjects (git auto-generated).
#
# Bypass with SKIP_CONVENTIONAL_GATE=1.

# shellcheck source=lib/commit-msg.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/commit-msg.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

case "$COMMAND" in
  *"git commit --help"*|*"git commit -h"*) exit 0 ;;
  *"git commit"*) ;;
  *) exit 0 ;;
esac

[ "$SKIP_CONVENTIONAL_GATE" = "1" ] && exit 0
commit_reuses_message "$COMMAND" && exit 0

# The subject is the first non-blank line of the message.
SUBJECT=$(extract_commit_msg "$COMMAND" | awk 'NF { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print; exit }')

# Could not extract a subject - let it through; not our concern to second-guess.
[ -z "$SUBJECT" ] && exit 0

# Git auto-generates Merge / Revert subjects on certain operations.
case "$SUBJECT" in
  "Merge "*|"Revert "*) exit 0 ;;
esac

if ! echo "$SUBJECT" | grep -qE '^(feat|fix|refactor|docs|chore|test|ci|perf|build|style|revert)(\([^)]+\))?!?: .+'; then
  echo "[pre-commit-conventional-gate] Commit subject does not match the conventional-commits format." >&2
  echo "Subject: $SUBJECT" >&2
  echo "Expected: <type>(<scope>)?!?: <description>" >&2
  echo "Allowed types: feat|fix|refactor|docs|chore|test|ci|perf|build|style|revert" >&2
  echo "Per rules/git-conventions.md." >&2
  echo "(Bypass: SKIP_CONVENTIONAL_GATE=1)" >&2
  exit 2
fi

exit 0
