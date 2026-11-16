#!/bin/bash
# Pre-commit Co-Authored-By gate.
# PreToolUse hook on Bash(git commit *) and Bash(git -C *). Blocks the commit
# when the command string contains a Co-Authored-By trailer in any case. Per
# rules/git-conventions.md: never add Co-Authored-By or any AI attribution.
# Exit 2 blocks the action and feeds the message back to Claude.
# Bypass with SKIP_COAUTHOR_GATE=1.

# shellcheck source=lib/resolve-repo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/resolve-repo.sh"
# shellcheck source=lib/hook.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/hook.sh"

hook_read

git_runs "$COMMAND" commit || exit 0
git_args_ask_help && exit 0

hook_bypass SKIP_COAUTHOR_GATE && exit 0

# The whole command is searched, so a trailer in -m, a heredoc, or a -F path
# all count.
if echo "$COMMAND" | grep -qiE '\bco-authored-by:'; then
  hook_block pre-commit-coauthor-gate SKIP_COAUTHOR_GATE \
    "Refusing to commit with Co-Authored-By trailer." \
    "Per rules/git-conventions.md, never add Co-Authored-By or any AI attribution to commits." \
    "Remove the trailer from the commit message and re-run."
fi

exit 0
