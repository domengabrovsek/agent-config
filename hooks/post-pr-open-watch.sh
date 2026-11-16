#!/bin/bash
# PostToolUse hook: after `gh pr create` or `gh pr ready` succeeds, tell the
# agent to watch the PR until scripts/pr-ready.sh reports it ready. A PR left
# with failing CI or unanswered bot threads otherwise sits until someone looks.
#
# Always exits 0. Bypass with SKIP_PR_WATCH=1.

[ "${SKIP_PR_WATCH:-}" = "1" ] && exit 0

# shellcheck source=lib/resolve-repo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/resolve-repo.sh"
# shellcheck source=lib/context.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/context.sh"
# shellcheck source=lib/once.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/once.sh"
# shellcheck source=lib/hook.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/hook.sh"

hook_read
first_run_for_call "$INPUT" post-pr-open-watch || exit 0

# The flags below come from the parsed create or ready call, so a flag
# spelled inside a quoted title or body never counts.
gh_runs "$COMMAND" "$CWD" "pr create|pr ready" || exit 0
git_args_ask_help && exit 0
git_args_have --dry-run --undo && exit 0
# A draft stays with the user until they run gh pr ready, which arms the watch.
[ "$GIT_SUB" = "gh pr create" ] && git_args_have --draft --draft=true -d && exit 0

OUTPUT=$(echo "$INPUT" | jq -r '.tool_response | if type == "object" then "\(.stdout // "")\n\(.stderr // "")" else tostring end')

case "$GIT_SUB" in
  "gh pr create")
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
    set -- ${GIT_ARGS[@]+"${GIT_ARGS[@]}"}
    while [ $# -gt 0 ]; do
      case "$1" in
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

emit_context PostToolUse "$CTX"
exit 0
