#!/bin/bash
# Tests for scripts/pr-ready.sh and hooks/post-pr-open-watch.sh. A stub gh on
# PATH serves the PR view and review threads from files each case writes.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
READY="$PROJECT_DIR/scripts/pr-ready.sh"
HOOK="$PROJECT_DIR/hooks/post-pr-open-watch.sh"
# Assembled so this file never carries the literal phrase other hooks trigger on.
GH_CREATE="gh ""pr create"
GH_READY="gh ""pr ready"
PASSED=0
FAILED=0

TMP_ROOT=$(cd "${TMPDIR:-/tmp}" && pwd)
TEST_DIR=$(cd "$(mktemp -d "$TMP_ROOT/pr-ready-test.XXXXXX")" && pwd)

cleanup() {
  case "$TEST_DIR" in
    "$TMP_ROOT"/pr-ready-test.*) rm -rf "$TEST_DIR" ;;
    *) echo "Refusing to clean unexpected test path: $TEST_DIR" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/gh" <<'STUB'
#!/bin/bash
[ -f "$STUB_DIR/fail" ] && exit 1
case "$1 $2" in
  "pr view") cat "$STUB_DIR/view.json" ;;
  "api graphql") cat "$STUB_DIR/threads.json" ;;
  "api repos/"*) cat "$STUB_DIR/workflows" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$TEST_DIR/bin/gh"
export PATH="$TEST_DIR/bin:$PATH"
export STUB_DIR="$TEST_DIR"
echo 1 > "$TEST_DIR/workflows"
export PR_READY_INTERVAL=0

pass() { PASSED=$((PASSED + 1)); echo "ok - $1"; }
fail() { FAILED=$((FAILED + 1)); echo "not ok - $1" >&2; }

URL="https://github.com/acme/app/pull/7"

# view <state> <isDraft> <mergeable> <mergeStateStatus> <reviewDecision> <checks-json>
view() {
  jq -n --arg url "$URL" --arg state "$1" --argjson draft "$2" --arg m "$3" \
    --arg ms "$4" --arg rd "$5" --argjson checks "$6" '{
      url: $url, number: 7, state: $state, isDraft: $draft, mergeable: $m,
      mergeStateStatus: $ms, reviewDecision: $rd, statusCheckRollup: $checks
    }' > "$TEST_DIR/view.json"
}

# threads <nodes-json> [has-next-page]
threads() {
  jq -n --argjson n "$1" --argjson more "${2:-false}" \
    '{data:{repository:{pullRequest:{reviewThreads:{pageInfo:{hasNextPage:$more},nodes:$n}}}}}' \
    > "$TEST_DIR/threads.json"
}

BOT_THREAD='{"id":"T2","isResolved":false,"path":"b.ts","line":9,"comments":{"nodes":[{"author":{"__typename":"Bot","login":"github-actions"},"url":"u2"}]}}'
HUMAN_THREAD='{"id":"T3","isResolved":false,"path":"c.ts","line":4,"comments":{"nodes":[{"author":{"__typename":"User","login":"alice"},"url":"u3"}]}}'

GREEN='[{"__typename":"CheckRun","name":"Gate","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"Reply","status":"COMPLETED","conclusion":"SKIPPED"}]'
RESOLVED='[{"id":"T1","isResolved":true,"path":"a.ts","line":1,"comments":{"nodes":[{"author":{"login":"bot"},"url":"u1"}]}}]'

# assert_ready <name> <want-exit> <want-substring> [args...]
assert_ready() {
  local name="$1" want="$2" needle="$3" out got
  shift 3
  out=$(bash "$READY" "$@" 2>&1)
  got=$?
  if [ "$got" -eq "$want" ] && echo "$out" | grep -qF -- "$needle"; then pass "$name"; else
    echo "    want exit $want with '$needle', got $got: $out" >&2
    fail "$name"
  fi
}

echo "== pr-ready =="
view OPEN false MERGEABLE CLEAN "" "$GREEN"; threads "$RESOLVED"
assert_ready "green, mergeable, threads resolved is ready" 0 "READY $URL"

view OPEN false MERGEABLE UNSTABLE "" '[{"__typename":"CheckRun","name":"Shell Tests","status":"COMPLETED","conclusion":"FAILURE"}]'
assert_ready "a failed check blocks" 1 "check-failing: Shell Tests"

view OPEN false MERGEABLE CLEAN "" '[{"__typename":"CheckRun","name":"Lint","status":"IN_PROGRESS","conclusion":null}]'
assert_ready "a running check blocks" 1 "check-pending: Lint"

view OPEN false MERGEABLE CLEAN "" '[{"__typename":"StatusContext","context":"ci/legacy","state":"ERROR"}]'
assert_ready "a failed commit status blocks" 1 "check-failing: ci/legacy"

view OPEN false MERGEABLE CLEAN "" "$GREEN"
threads "[$BOT_THREAD]"
assert_ready "an unresolved bot thread blocks with its id and kind" 1 "thread: T2 bot github-actions b.ts:9 u2"

threads "[$HUMAN_THREAD]"
assert_ready "only a human thread left is waiting on a human" 4 "thread: T3 human alice c.ts:4 u3"
assert_ready "the waiting state is named" 4 "WAITING_ON_HUMAN $URL"
assert_ready "watch ends while waiting on a human" 4 "WAITING_ON_HUMAN" --watch

threads "[$BOT_THREAD,$HUMAN_THREAD]"
assert_ready "a bot thread beside a human one is still agent work" 1 "NOT_READY $URL"

threads "$RESOLVED" true
assert_ready "more than 100 threads blocks" 1 "threads-truncated"

threads "$RESOLVED"
view OPEN false CONFLICTING DIRTY "" "$GREEN"
assert_ready "conflicts block" 1 "conflicts"

view OPEN false MERGEABLE BEHIND "" "$GREEN"
assert_ready "a branch behind its base blocks" 1 "behind-base"

view OPEN true MERGEABLE DRAFT "" "$GREEN"
assert_ready "a draft waits on the user" 4 "draft"

view OPEN false MERGEABLE CLEAN "" '[]'
assert_ready "no checks yet in a repo with workflows is pending" 1 "check-pending: no checks registered yet"
echo 0 > "$TEST_DIR/workflows"
assert_ready "no checks in a repo without workflows is ready" 0 "READY $URL"
echo 1 > "$TEST_DIR/workflows"

view OPEN false MERGEABLE BLOCKED CHANGES_REQUESTED "$GREEN"
assert_ready "requested changes wait on a human" 4 "changes-requested"

view OPEN false MERGEABLE BLOCKED REVIEW_REQUIRED '[{"__typename":"CheckRun","name":"Lint","status":"COMPLETED","conclusion":"FAILURE"}]'
assert_ready "a failing check beside a required review is still agent work" 1 "check-failing: Lint"

view MERGED false MERGEABLE CLEAN "" "$GREEN"
assert_ready "a merged PR reports done" 3 "state=MERGED"

touch "$TEST_DIR/fail"
assert_ready "a gh failure is an error" 2 ""
rm "$TEST_DIR/fail"

view OPEN false MERGEABLE CLEAN "" "$GREEN"
assert_ready "watch exits once ready" 0 "READY $URL" --watch

echo
echo "== post-pr-open-watch hook =="

# assert_hook <name> <command> <stdout> <want-substring or empty for silence>
assert_hook() {
  local name="$1" command="$2" stdout="$3" needle="$4" out
  out=$(COMMAND="$command" STDOUT="$stdout" python3 -c 'import json,os; print(json.dumps({"tool_input":{"command":os.environ["COMMAND"]},"tool_response":{"stdout":os.environ["STDOUT"]}}))' \
    | bash "$HOOK" 2>&1)
  if [ -z "$needle" ]; then
    if [ -z "$out" ]; then pass "$name"; else echo "    want silence, got: $out" >&2; fail "$name"; fi
  elif echo "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -qF -- "$needle"; then
    pass "$name"
  else
    echo "    want '$needle', got: $out" >&2
    fail "$name"
  fi
}

assert_hook "a created PR gets a watch on its URL" "$GH_CREATE --title t --body b" "$URL" \
  "pr-ready.sh --watch $URL"
assert_hook "the context says how to resolve a bot thread" "$GH_CREATE --title t" "$URL" \
  "resolveReviewThread"
assert_hook "a failed create stays silent" "$GH_CREATE --title t" "error: no commits" ""
MARKED='✓ Pull request acme/app#7 is marked as "ready for review"'
assert_hook "a ready PR with no argument watches the branch PR" "$GH_READY" "$MARKED" "<this branch's PR>"
assert_hook "a ready PR number is watched" "$GH_READY 7 && echo done" "$MARKED" "pr-ready.sh --watch 7"
assert_hook "a ready PR number with a repo becomes a URL" "$GH_READY -R acme/app 7" "$MARKED" \
  "pr-ready.sh --watch $URL"
assert_hook "a ready that did not mark the PR stays silent" "$GH_READY 7" \
  '! Pull request acme/app#7 is already "ready for review"' ""
assert_hook "undo stays silent" "$GH_READY 7 --undo" "$MARKED" ""
assert_hook "a draft create stays silent" "$GH_CREATE --draft --title t" "$URL" ""
assert_hook "a short draft flag stays silent" "$GH_CREATE -d --title t" "$URL" ""
assert_hook "a create with a -d in the body is not a draft" "$GH_CREATE --title t --body x-d" "$URL" \
  "pr-ready.sh --watch $URL"
assert_hook "other commands stay silent" "gh pr view 7" "$URL" ""
assert_hook "help stays silent" "$GH_CREATE --help" "$URL" ""
OUT=$(SKIP_PR_WATCH=1 bash "$HOOK" <<< '{"tool_input":{"command":"gh pr create"}}')
if [ -z "$OUT" ]; then pass "SKIP_PR_WATCH bypasses"; else fail "SKIP_PR_WATCH bypasses"; fi

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
