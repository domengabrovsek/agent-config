#!/bin/bash
# PostToolUse hook: after `gh pr create` or `gh pr ready` succeeds, tell the
# agent to watch the PR until scripts/pr-ready.sh reports it ready. A PR left
# with failing CI or unanswered bot threads otherwise sits until someone looks.
#
# Always exits 0. Bypass with SKIP_PR_WATCH=1.

[ "${SKIP_PR_WATCH:-}" = "1" ] && exit 0

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

case "$COMMAND" in
  *"gh pr create"*|*"gh pr ready"*) ;;
  *) exit 0 ;;
esac
case "$COMMAND" in
  *" --help"*|*" -h"*|*"--dry-run"*) exit 0 ;;
esac

OUTPUT=$(echo "$INPUT" | jq -r '.tool_response | if type == "object" then (.stdout // "") else tostring end')
URL=$(echo "$OUTPUT" | grep -oE 'https://github\.com/[^/ ]+/[^/ ]+/pull/[0-9]+' | head -1)

# gh pr create prints the URL on success; no URL means it failed.
case "$COMMAND" in
  *"gh pr create"*) [ -z "$URL" ] && exit 0 ;;
esac

TARGET="$URL"
[ -z "$TARGET" ] && TARGET="<this branch's PR>"

CTX=$(cat <<EOF
[pr-watch] Drive $TARGET until it is ready to merge.
Arm a Monitor on: bash ~/.agents/scripts/pr-ready.sh --watch $URL
It prints READY when done. Re-arm it if the Monitor expires first. For each blocker it prints:
- check-failing: follow /ci (classify transient vs real, fix real failures, push)
- thread by a bot: fix or answer it, reply in-thread, then resolve it with
  gh api graphql -f query='mutation{resolveReviewThread(input:{threadId:"<id>"}){thread{isResolved}}}'
- thread by a human: draft the reply for the user. Leave it unresolved
- behind-base: gh pr update-branch
- conflicts: /resolve-conflicts
- review-required or changes-requested: report under Blocked on me
Never merge. The user merges.
EOF
)

jq -n --arg ctx "$CTX" '{
  continue: true,
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'
exit 0
