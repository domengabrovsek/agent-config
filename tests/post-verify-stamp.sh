#!/bin/bash
# Tests for hooks/post-verify-stamp.sh.
#
# A successful foreground `npm run verify` on a clean tree writes HEAD to
# <git-dir>/verify-passed. Any command whose exit code could come from
# something else, a background run, a dirty tree or a repo without `verify`
# leaves no stamp.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
HOOK="$PROJECT_DIR/hooks/post-verify-stamp.sh"
harness_init post-verify-stamp

# probe_repo <dir> <scripts-json>
probe_repo() {
  mkdir -p "$1"
  printf '{ "name": "probe", "private": true, "scripts": %s }\n' "$2" > "$1/package.json"
  make_repo "$1"
}

stamp_file() { echo "$(git -C "$1" rev-parse --path-format=absolute --git-dir)/verify-passed"; }

# run_hook <payload-cwd> <command> [background] [interrupted]
run_hook() {
  CWD="$1" COMMAND="$2" BG="${3:-false}" INT="${4:-false}" python3 -c '
import json, os
print(json.dumps({
  "cwd": os.environ["CWD"],
  "tool_input": {"command": os.environ["COMMAND"], "run_in_background": os.environ["BG"] == "true"},
  "tool_response": {"stdout": "", "stderr": "", "interrupted": os.environ["INT"] == "true"},
}))' | (cd "$TEST_ROOT" && CLAUDE_PROJECT_DIR="" SKIP_VERIFY_STAMP="" bash "$HOOK")
}

# assert_stamp <name> <repo> <want: head|none> <payload-cwd> <command> [background] [interrupted]
assert_stamp() {
  local name="$1" repo="$2" want="$3" got
  shift 3
  rm -f "$(stamp_file "$repo")"
  run_hook "$@" > /dev/null
  got=$(cat "$(stamp_file "$repo")" 2>/dev/null || echo none)
  [ "$want" = head ] && want=$(git -C "$repo" rev-parse HEAD)
  if [ "$got" = "$want" ]; then
    pass "$name"
  else
    echo "    want $want, got $got" >&2
    fail "$name"
  fi
}

REPO="$TEST_ROOT/repo"
HUB="$TEST_ROOT/hub"
BARE="$TEST_ROOT/no-verify"
probe_repo "$REPO" '{ "verify": "exit 0" }'
probe_repo "$BARE" '{ "test": "exit 0" }'
mkdir -p "$HUB" "$REPO/packages/sub"

echo "== stamps =="
assert_stamp "plain npm run verify stamps HEAD" "$REPO" head "$REPO" "npm run verify"
assert_stamp "a leading cd from another dir stamps the target" "$REPO" head "$HUB" "cd $REPO && npm run verify"
assert_stamp "a relative cd resolves from the cwd before the cd" "$REPO" head "$TEST_ROOT" \
  "cd repo/packages/sub && npm run verify"
assert_stamp "a relative cd still stamps when the cwd is already the target" "$REPO" head "$REPO/packages/sub" \
  "cd repo/packages/sub && npm run verify"
HOME="$TEST_ROOT" assert_stamp "a ~ cd path expands to HOME" "$REPO" head "$HUB" "cd ~/repo && npm run verify"
assert_stamp "env assignments and a redirect outside the repo are allowed" "$REPO" head "$REPO" \
  "CI=1 PUBLIC_X=y npm run verify > $TEST_ROOT/out.log 2>&1"
assert_stamp "a subdirectory finds the repo's package.json" "$REPO" head "$REPO/packages/sub" "npm run verify"
out=$(run_hook "$REPO" "npm run verify")
if printf '%s' "$out" | grep -qF "[verify-stamp] Recorded a verify pass"; then
  pass "it tells the agent the stamp was written"
else
  fail "it tells the agent the stamp was written"
fi

echo
echo "== no stamp =="
assert_stamp "verify:fast does not stamp" "$REPO" none "$REPO" "npm run verify:fast"
assert_stamp "a pipe hides the exit code" "$REPO" none "$REPO" "npm run verify | tail -5"
assert_stamp "a ; hides the exit code" "$REPO" none "$REPO" "npm run verify; echo done"
assert_stamp "|| hides the exit code" "$REPO" none "$REPO" "npm run verify || true"
assert_stamp "a chained cd prefix could name the wrong repo" "$REPO" none "$HUB" \
  "cd $REPO; cd $BARE && npm run verify"
assert_stamp "a background run has not finished" "$REPO" none "$REPO" "npm run verify" true
assert_stamp "an interrupted run does not stamp" "$REPO" none "$REPO" "npm run verify" false true
assert_stamp "an unrelated command does not stamp" "$REPO" none "$REPO" "npm test"
touch "$REPO/dirty"
assert_stamp "a dirty tree does not stamp" "$REPO" none "$REPO" "npm run verify"
rm "$REPO/dirty"
# The hook never runs the command, so create the log the redirect would write.
touch "$REPO/out.log"
assert_stamp "a log redirected into the repo dirties the tree" "$REPO" none "$REPO" \
  "npm run verify > out.log 2>&1"
rm "$REPO/out.log"
assert_stamp "a repo without verify does not stamp" "$BARE" none "$BARE" "npm run verify"
rm -f "$(stamp_file "$REPO")"
echo '{"cwd":"'"$REPO"'","tool_input":{"command":"npm run verify"}}' \
  | (cd "$TEST_ROOT" && SKIP_VERIFY_STAMP=1 bash "$HOOK") > /dev/null
if [ -e "$(stamp_file "$REPO")" ]; then fail "the bypass writes nothing"; else pass "the bypass writes nothing"; fi

finish
