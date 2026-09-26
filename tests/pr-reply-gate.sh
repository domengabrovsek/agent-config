#!/bin/bash
# Tests for hooks/pre-pr-reply-gate.sh. A stub gh on PATH answers the parent
# comment lookup: 111 is a bot, 222 is a human, 333 fails. Every comment the
# agent posts must also end with the agent footer.

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
GH_PR_COMMENT="gh ""pr comment"
GH_ISSUE_COMMENT="gh ""issue comment"
SIGNATURE="<sub>Posted by Claude Code on behalf of @owner</sub>"
FOOTER=$'\n\n'"$SIGNATURE"

echo "== human replies =="
assert_gate "a reply to a bot passes" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments/111/replies -f body=\"Fixed in abc123. $FOOTER\"" 0
assert_gate "a reply to a human is blocked" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments/222/replies -f body=\"Done. $FOOTER\"" 2
assert_gate "an in_reply_to comment to a human is blocked" \
  "$GH_API repos/acme/app/pulls/7/comments -F in_reply_to=222 -f body=\"Done. $FOOTER\"" 2
assert_gate "an in_reply_to comment to a bot passes" \
  "$GH_API repos/acme/app/pulls/7/comments -F in_reply_to=111 -f body=\"Done. $FOOTER\"" 0
assert_gate "a failed author lookup blocks" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments/333/replies -f body=\"Done. $FOOTER\"" 2
assert_gate "a read-only gh api call passes" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments" 0
assert_gate "an unrelated command passes" \
  "git status" 0

echo
echo "== footer =="
assert_gate "a bot reply without the footer is blocked" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments/111/replies -f body=\"Fixed in abc123.\"" 2
assert_gate "a new api comment without the footer is blocked" \
  "$GH_API repos/acme/app/issues/7/comments -f body=\"Done.\"" 2
assert_gate "a PR comment with the footer passes" \
  "$GH_PR_COMMENT 7 --body \"Done. $FOOTER\"" 0
assert_gate "a PR comment without the footer is blocked" \
  "$GH_PR_COMMENT 7 --body \"Done.\"" 2
assert_gate "an issue comment without the footer is blocked" \
  "$GH_ISSUE_COMMENT 7 -b \"Done.\"" 2
printf 'Done.\n\n%s\n' "$FOOTER" > "$TEST_DIR/reply.md"
assert_gate "a body file with the footer passes" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments/111/replies -F body=@reply.md" 0
assert_gate "a --body-file with the footer passes" \
  "$GH_PR_COMMENT 7 --body-file reply.md" 0
printf 'Done.\n' > "$TEST_DIR/bare.md"
assert_gate "a --body-file without the footer is blocked" \
  "$GH_PR_COMMENT 7 --body-file bare.md" 2
if payload "$GH_PR_COMMENT 7 --body \"Done.\"" | SKIP_REPLY_FOOTER=1 bash "$GATE" >/dev/null 2>&1; then
  pass "SKIP_REPLY_FOOTER lets a comment through"
else
  fail "SKIP_REPLY_FOOTER lets a comment through"
fi
assert_gate "help is not gated" \
  "$GH_PR_COMMENT --help" 0
assert_gate "a footer outside the body does not count" \
  "echo \"$FOOTER\" && $GH_PR_COMMENT 7 --body \"Done.\"" 2
assert_gate "a footer on the same line as the text is blocked" \
  "$GH_PR_COMMENT 7 --body \"Done. $SIGNATURE\"" 2
assert_gate "a footer on the next line without a blank line is blocked" \
  "$GH_PR_COMMENT 7 --body \"Done.
$SIGNATURE\"" 2
assert_gate "a footer before the end does not count" \
  "$GH_PR_COMMENT 7 --body \"$FOOTER Done.\"" 2
assert_gate "a heredoc body ending in the footer passes" \
  "$GH_PR_COMMENT 7 --body \"\$(cat <<'EOF'
Done.

$FOOTER
EOF
)\"" 0
assert_gate "an unparsed body flag is checked, not skipped" \
  "$GH_PR_COMMENT 7 --body Done" 2
assert_gate "a -F body file with the footer passes" \
  "$GH_PR_COMMENT 7 -F reply.md" 0

echo
echo "== reviews =="
GH_PR_REVIEW="gh ""pr review"
assert_gate "a review comment without the footer is blocked" \
  "$GH_PR_REVIEW 7 --comment -b \"Looks off.\"" 2
assert_gate "a review comment with the footer passes" \
  "$GH_PR_REVIEW 7 --request-changes -b \"Looks off. $FOOTER\"" 0
assert_gate "an approval without a body passes" \
  "$GH_PR_REVIEW 7 --approve" 0

echo
echo "== bodies that are not comments =="
assert_gate "a PR body posted through gh api passes" \
  "$GH_API repos/acme/app/pulls -f title=\"feat: x\" -f body=\"Adds x.\"" 0
assert_gate "a PR body edit through gh api passes" \
  "$GH_API -X PATCH repos/acme/app/pulls/7 -f body=\"Adds x.\"" 0
assert_gate "a release body passes" \
  "$GH_API repos/acme/app/releases -f tag_name=v1 -f body=\"Notes.\"" 0

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
