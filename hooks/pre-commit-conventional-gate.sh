#!/bin/bash
# Pre-commit conventional-commit format gate.
# PreToolUse hook on Bash(git commit *) and Bash(git -C *). Extracts the
# subject line from the commit command and checks it with is_conventional
# from lib/commit-msg.sh, per rules/git-conventions.md.
#
# Skips amend / fixup / squash / no-edit (auto-generated messages or reusing
# existing) and Merge / Revert subjects (git auto-generated).
#
# Bypass with SKIP_CONVENTIONAL_GATE=1.

# shellcheck source=lib/commit-msg.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/commit-msg.sh"
# shellcheck source=lib/hook.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/hook.sh"

hook_read

git_runs "$COMMAND" commit || exit 0
git_args_ask_help && exit 0

hook_bypass SKIP_CONVENTIONAL_GATE && exit 0
commit_reuses_message "$COMMAND" && exit 0

# The subject is the first non-blank line of the message.
SUBJECT=$(extract_commit_msg "$COMMAND" | awk 'NF { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print; exit }')

# A message from a file or the editor is not in the command, so there is
# nothing to check here.
[ -z "$SUBJECT" ] && exit 0

# Git auto-generates Merge / Revert subjects on certain operations.
case "$SUBJECT" in
  "Merge "*|"Revert "*) exit 0 ;;
esac

if ! is_conventional "$SUBJECT"; then
  hook_block pre-commit-conventional-gate SKIP_CONVENTIONAL_GATE \
    "Commit subject does not match the conventional-commits format." \
    "Subject: $SUBJECT" \
    "Expected: <type>(<scope>)?!?: <description>" \
    "Allowed types: $CONVENTIONAL_TYPES" \
    "Per rules/git-conventions.md."
fi

exit 0
