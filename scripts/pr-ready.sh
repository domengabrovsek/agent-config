#!/bin/bash
# Reports whether a GitHub PR is ready to merge: open, not a draft, every
# check green, no conflicts, not behind its base, and no unresolved review
# thread. Each blocker prints on its own line so a Monitor sees exactly what
# changed between polls.
#
# Usage:
#   pr-ready.sh [<pr>]           one check; <pr> is a number, URL, or branch
#   pr-ready.sh --watch [<pr>]   poll, print only on change, exit when ready
#
# Exit codes: 0 ready, 1 not ready, 2 error, 3 PR merged or closed.
# PR_READY_INTERVAL sets the watch poll in seconds (default 30).

set -u

WATCH=0
if [ "${1:-}" = "--watch" ]; then
  WATCH=1
  shift
fi
PR="${1:-}"

# Prints the report and returns its exit code.
check() {
  local view url owner repo number threads
  # shellcheck disable=SC2086
  view=$(gh pr view $PR --json url,number,state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup 2>/dev/null) || return 2
  url=$(echo "$view" | jq -r '.url')
  number=$(echo "$view" | jq -r '.number')
  owner=$(echo "$url" | cut -d/ -f4)
  repo=$(echo "$url" | cut -d/ -f5)

  case "$(echo "$view" | jq -r '.state')" in
    MERGED|CLOSED)
      echo "DONE $url state=$(echo "$view" | jq -r '.state')"
      return 3
      ;;
  esac

  threads=$(gh api graphql \
    -F owner="$owner" -F repo="$repo" -F number="$number" \
    -f query='query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100){nodes{id isResolved path line comments(first:1){nodes{author{login} url}}}}}}}' \
    2>/dev/null) || return 2

  local reasons
  reasons=$(jq -rn --argjson v "$view" --argjson t "$threads" '
    def ok_conclusion: . == "SUCCESS" or . == "SKIPPED" or . == "NEUTRAL";
    [
      (if $v.isDraft then "draft" else empty end),
      ($v.statusCheckRollup[]? |
        if .__typename == "StatusContext" then
          if .state == "PENDING" or .state == "EXPECTED" then "check-pending: \(.context)"
          elif .state == "SUCCESS" then empty
          else "check-failing: \(.context)" end
        elif .status != "COMPLETED" then "check-pending: \(.name)"
        elif (.conclusion | ok_conclusion) then empty
        else "check-failing: \(.name)" end),
      (if $v.mergeable == "CONFLICTING" then "conflicts"
       elif $v.mergeable == "UNKNOWN" then "mergeable-unknown"
       else empty end),
      (if $v.mergeStateStatus == "BEHIND" then "behind-base" else empty end),
      (if $v.reviewDecision == "CHANGES_REQUESTED" then "changes-requested"
       elif $v.reviewDecision == "REVIEW_REQUIRED" then "review-required"
       else empty end),
      ($t.data.repository.pullRequest.reviewThreads.nodes[]? | select(.isResolved | not) |
        "thread: \(.id) \(.comments.nodes[0].author.login // "unknown") \(.path):\(.line // "-") \(.comments.nodes[0].url // "")")
    ] | .[]')

  if [ -z "$reasons" ]; then
    echo "READY $url"
    return 0
  fi
  echo "NOT_READY $url"
  echo "$reasons" | sed 's/^/  /'
  return 1
}

if [ "$WATCH" -eq 0 ]; then
  check
  exit $?
fi

LAST=""
ERRORS=0
while true; do
  OUT=$(check)
  CODE=$?
  if [ "$CODE" -eq 2 ]; then
    ERRORS=$((ERRORS + 1))
    if [ "$ERRORS" -ge 5 ]; then
      echo "ERROR persistent-failure: gh failed 5 times in a row"
      exit 2
    fi
  else
    ERRORS=0
    if [ "$OUT" != "$LAST" ]; then
      echo "$OUT"
      LAST="$OUT"
    fi
    [ "$CODE" -eq 0 ] || [ "$CODE" -eq 3 ] && exit "$CODE"
  fi
  sleep "${PR_READY_INTERVAL:-30}"
done
