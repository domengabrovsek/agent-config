#!/bin/bash
# Pre-PR body gate: blocks a PR whose title or body breaks
# rules/git-conventions.md.
#
# PreToolUse hook on Bash(gh pr create *) and Bash(gh pr edit *). It covers the
# PR surface; hooks/pre-commit-coauthor-gate.sh covers commits. The PR title and
# body are where a "Generated with" footer or a local state path reach a reviewer.
#
# Two checks:
#   attribution  no Co-Authored-By trailer, no AI "Generated with" footer
#   local state  no .claude/state/ path, untracked and invisible to reviewers
#
# Exit 2 blocks the action and feeds the message back to Claude.
# Bypass with SKIP_PR_BODY_GATE=1.

# shellcheck source=lib/pr-body.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/pr-body.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

case "$COMMAND" in
  *"gh pr create --help"*|*"gh pr create -h"*) exit 0 ;;
  *"gh pr edit --help"*|*"gh pr edit -h"*) exit 0 ;;
  *"gh pr create"*|*"gh pr edit"*) ;;
  *) exit 0 ;;
esac

[ "$SKIP_PR_BODY_GATE" = "1" ] && exit 0

# The rules cover titles as well as bodies, and a --body-file body never
# appears in the command, so both halves go into one haystack.
BODY=$(extract_pr_body "$COMMAND")
HAYSTACK=$(printf '%s\n%s' "$COMMAND" "$BODY")

FAILED=0

report() {
  [ "$FAILED" -eq 0 ] && echo "[pre-pr-body-gate] Refusing to write this PR." >&2
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
