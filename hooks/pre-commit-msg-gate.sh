#!/bin/bash
# Pre-commit message gate: checks the message a `git commit` command carries,
# per rules/git-conventions.md.
#
# PreToolUse hook on Bash(git commit *) and Bash(git -C *). Two checks:
#   co-author     no Co-Authored-By trailer anywhere in the command, so a
#                 trailer in -m, a heredoc, or a -F path all count
#   conventional  the subject reads <type>(<scope>)?!?: <description>, checked
#                 with is_conventional from lib/commit-msg.sh
#
# The conventional check skips amend, fixup, squash and no-edit commits, whose
# message git generates or reuses, and Merge and Revert subjects, which git
# generates. A message from a file or the editor is not in the command, so it
# has no subject to check.
#
# Exit 2 blocks the commit and feeds the message back to the agent.
# Bypass with SKIP_COAUTHOR_GATE=1 or SKIP_CONVENTIONAL_GATE=1, one per check.

# shellcheck source=lib/commit-msg.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/commit-msg.sh"
# shellcheck source=lib/attribution.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/attribution.sh"
# shellcheck source=lib/once.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/once.sh"
# shellcheck source=lib/hook.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/hook.sh"

hook_read
first_run_for_call "$INPUT" pre-commit-msg-gate || exit 0

git_runs "$COMMAND" commit || exit 0
git_args_ask_help && exit 0

if ! hook_bypass SKIP_COAUTHOR_GATE && [ -n "$(attribution_problems "$COMMAND" coauthor)" ]; then
  hook_block pre-commit-msg-gate SKIP_COAUTHOR_GATE \
    "Refusing to commit with Co-Authored-By trailer." \
    "Per rules/git-conventions.md, never add Co-Authored-By or any AI attribution to commits." \
    "Remove the trailer from the commit message and re-run."
fi

hook_bypass SKIP_CONVENTIONAL_GATE && exit 0
commit_reuses_message "$COMMAND" && exit 0

# The subject is the first non-blank line of the message.
SUBJECT=$(extract_commit_msg "$COMMAND" | awk 'NF { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print; exit }')
[ -z "$SUBJECT" ] && exit 0

case "$SUBJECT" in
  "Merge "*|"Revert "*) exit 0 ;;
esac

if ! is_conventional "$SUBJECT"; then
  hook_block pre-commit-msg-gate SKIP_CONVENTIONAL_GATE \
    "Commit subject does not match the conventional-commits format." \
    "Subject: $SUBJECT" \
    "Expected: <type>(<scope>)?!?: <description>" \
    "Allowed types: $CONVENTIONAL_TYPES" \
    "Per rules/git-conventions.md."
fi

exit 0
