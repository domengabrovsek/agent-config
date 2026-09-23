#!/bin/bash
# Tests for hooks/pre-pr-reply-gate.sh. A stub gh on PATH answers the parent
# comment lookup: 111 is a bot, 222 is a human, 333 fails.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
GATE="$PROJECT_DIR/hooks/pre-pr-reply-gate.sh"
PASSED=0
FAILED=0

TMP_ROOT=$(cd "${TMPDIR:-/tmp}" && pwd)
TEST_DIR=$(cd "$(mktemp -d "$TMP_ROOT/pr-reply-gate-test.XXXXXX")" && pwd)

cleanup() {
  case "$TEST_DIR" in
    "$TMP_ROOT"/pr-reply-gate-test.*) rm -rf "$TEST_DIR" ;;
    *) echo "Refusing to clean unexpected test path: $TEST_DIR" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
  *pulls/comments/111*) echo "bot" ;;
  *pulls/comments/222*) echo "human:alice" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$TEST_DIR/bin/gh"
export PATH="$TEST_DIR/bin:$PATH"

pass() { PASSED=$((PASSED + 1)); echo "ok - $1"; }
fail() { FAILED=$((FAILED + 1)); echo "not ok - $1" >&2; }

payload() {
  COMMAND="$1" CWD="$TEST_DIR" python3 -c 'import json,os; print(json.dumps({"tool_input":{"command":os.environ["COMMAND"]},"cwd":os.environ["CWD"]}))'
}

# assert_gate <name> <command> <expected-exit>
assert_gate() {
  local name="$1" command="$2" want="$3" got
  payload "$command" | bash "$GATE" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then pass "$name"; else
    echo "    want exit $want, got $got" >&2
    fail "$name"
  fi
}

GH_API="gh ""api"
assert_gate "a reply to a bot passes" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments/111/replies -f body=\"Fixed in abc123.\"" 0
assert_gate "a reply to a human is blocked" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments/222/replies -f body=\"Done.\"" 2
assert_gate "an in_reply_to comment to a human is blocked" \
  "$GH_API repos/acme/app/pulls/7/comments -F in_reply_to=222 -f body=\"Done.\"" 2
assert_gate "an in_reply_to comment to a bot passes" \
  "$GH_API repos/acme/app/pulls/7/comments -F in_reply_to=111 -f body=\"Done.\"" 0
assert_gate "a failed author lookup blocks" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments/333/replies -f body=\"Done.\"" 2
assert_gate "a read-only gh api call passes" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments" 0
assert_gate "an unrelated command passes" \
  "git status" 0

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
