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
  *" --help"*|*" -h"*|*"--dry-run"*|*"--undo"*) exit 0 ;;
esac

OUTPUT=$(echo "$INPUT" | jq -r '.tool_response | if type == "object" then "\(.stdout // "")\n\(.stderr // "")" else tostring end')

case "$COMMAND" in
  *"gh pr create"*)
    # gh pr create prints the URL on success; no URL means it failed.
    URL=$(echo "$OUTPUT" | grep -oE 'https://github\.com/[^/ ]+/[^/ ]+/pull/[0-9]+' | head -1)
    [ -z "$URL" ] && exit 0
    ;;
  *)
    # gh pr ready prints no URL, only this marker on success.
    echo "$OUTPUT" | grep -q 'is marked as "ready for review"' || exit 0
    # The PR is the first non-flag argument; -R/--repo takes a value.
    URL=""
    REPO=""
    set -f
    # shellcheck disable=SC2086
    set -- ${COMMAND#*gh pr ready}
    set +f
    while [ $# -gt 0 ]; do
      case "$1" in
        '&&'|'||'|';'|'|') break ;;
        -R|--repo) REPO="${2:-}"; shift 2 ;;
        --repo=*) REPO="${1#--repo=}"; shift ;;
        -*) shift ;;
        *) URL="$1"; break ;;
      esac
    done
    case "$URL" in
      [0-9]*) [ -n "$REPO" ] && URL="https://github.com/$REPO/pull/$URL" ;;
    esac
    ;;
esac

TARGET="$URL"
[ -z "$TARGET" ] && TARGET="<this branch's PR>"

CTX=$(cat <<EOF
[pr-watch] Drive $TARGET until it is ready to merge.
Arm a Monitor on: bash ~/.agents/scripts/pr-ready.sh --watch $URL
It ends on READY, or on WAITING_ON_HUMAN when only human blockers remain. Re-arm it if the Monitor expires first. For each blocker it prints:
- check-failing: follow /ci (classify transient vs real, fix real failures, push)
- thread ... bot: fix or answer it, reply in-thread, then resolve it with
  gh api graphql -f query='mutation{resolveReviewThread(input:{threadId:"<id>"}){thread{isResolved}}}'
- thread ... human: draft the reply for the user. Leave it unresolved
- behind-base: gh pr update-branch
- conflicts: /resolve-conflicts
- threads-truncated: list the remaining threads by hand
- review-required or changes-requested: report under Blocked on me
On WAITING_ON_HUMAN, report the remaining blockers under Blocked on me and stop.
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
