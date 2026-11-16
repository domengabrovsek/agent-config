#!/bin/bash
# Pre-PR body gate: blocks a PR or issue whose title or body breaks
# rules/git-conventions.md.
#
# PreToolUse hook on Bash(gh pr create *), Bash(gh pr edit *),
# Bash(gh issue create *), and Bash(gh issue edit *). It covers the PR and issue
# surface; hooks/pre-commit-coauthor-gate.sh covers commits. The title and body
# are where a "Generated with" footer or a local state path reach a reader.
#
# Two checks:
#   attribution  no Co-Authored-By trailer, no AI "Generated with" footer
#   local state  no .claude/state/ path, untracked and invisible to reviewers
#
# Exit 2 blocks the action and feeds the message back to Claude.
# Bypass with SKIP_PR_BODY_GATE=1.

# shellcheck source=lib/pr-body.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/pr-body.sh"
# shellcheck source=lib/once.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/once.sh"

INPUT=$(cat)
first_run_for_call "$INPUT" pre-pr-body-gate || exit 0
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

case "$COMMAND" in
  *"gh pr create --help"*|*"gh pr create -h"*) exit 0 ;;
  *"gh pr edit --help"*|*"gh pr edit -h"*) exit 0 ;;
  *"gh issue create --help"*|*"gh issue create -h"*) exit 0 ;;
  *"gh issue edit --help"*|*"gh issue edit -h"*) exit 0 ;;
  *"gh pr create"*|*"gh pr edit"*|*"gh issue create"*|*"gh issue edit"*) ;;
  *) exit 0 ;;
esac

[ "$SKIP_PR_BODY_GATE" = "1" ] && exit 0

# The rules cover titles as well as bodies, and a --body-file body never
# appears in the command, so both halves go into one haystack. Only the gh call
# counts: a state path in a command chained to it never reaches the PR. A
# body the gate cannot read, or a call that expands a variable, may be built
# by those other commands, so then the whole command counts.
BODY=$(extract_pr_body "$COMMAND")
SCOPE=$(pr_command_segment "$COMMAND")
if { [ -z "$BODY" ] && printf '%s\n' "$SCOPE" \
    | grep -qE '(^|[[:space:]])(-b|--body|-F|--body-file)([= ]|$)'; } \
  || printf '%s' "$SCOPE" | sed 's/\$(cat <<//g' | grep -q '[$`]'; then
  SCOPE=$COMMAND
fi
HAYSTACK=$(printf '%s\n%s' "$SCOPE" "$BODY")

FAILED=0

report() {
  [ "$FAILED" -eq 0 ] && echo "[pre-pr-body-gate] Refusing to write this PR or issue." >&2
  FAILED=1
  echo "  $1" >&2
}

if printf '%s' "$HAYSTACK" | grep -qiE '\bco-authored-by:'; then
  report "Co-Authored-By trailer. rules/git-conventions.md bans AI attribution."
fi

if printf '%s' "$HAYSTACK" | grep -qiE 'generated with.{0,40}(claude|codex|copilot|chatgpt)'; then
  report "A \"Generated with\" footer. rules/git-conventions.md bans AI attribution."
fi

if printf '%s' "$HAYSTACK" | grep -q '🤖'; then
  report "A robot emoji. It marks the attribution footer the same rule bans."
fi

if printf '%s' "$HAYSTACK" | grep -q '\.claude/state/'; then
  report "A .claude/state/ path. Those artifacts are untracked, so a reviewer cannot open them."
fi

if [ "$FAILED" -eq 1 ]; then
  echo "Rewrite the text and re-run." >&2
  echo "(Bypass: SKIP_PR_BODY_GATE=1)" >&2
  exit 2
fi

exit 0
