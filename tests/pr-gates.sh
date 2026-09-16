#!/bin/bash
# Tests for the PreToolUse PR gates: the pr mode of the prose gate, and the
# body gate that backs rules/git-conventions.md.
#
# Both read the body through hooks/lib/pr-body.sh, so the extraction shapes
# (--body, --body-file, heredoc) are exercised against both hooks. Both also
# run on edit as well as create: the create path was gated long before the
# edit path, which is the path a PR body actually gets rewritten on.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PROSE="$PROJECT_DIR/hooks/prose-gate.sh pr"
BODY="$PROJECT_DIR/hooks/pre-pr-body-gate.sh"
# Assembled so this file never carries the literal phrase the hooks trigger on.
GH_CREATE="gh ""pr create"
GH_EDIT="gh ""pr edit 12"
PASSED=0
FAILED=0

TMP_ROOT=$(cd "${TMPDIR:-/tmp}" && pwd)
TEST_DIR=$(cd "$(mktemp -d "$TMP_ROOT/pr-gates-test.XXXXXX")" && pwd)

cleanup() {
  case "$TEST_DIR" in
    "$TMP_ROOT"/pr-gates-test.*) rm -rf "$TEST_DIR" ;;
    *) echo "Refusing to clean unexpected test path: $TEST_DIR" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

pass() { PASSED=$((PASSED + 1)); echo "ok - $1"; }
fail() { FAILED=$((FAILED + 1)); echo "not ok - $1" >&2; }

payload() {
  COMMAND="$1" python3 -c 'import json,os,sys; print(json.dumps({"tool_input":{"command":os.environ["COMMAND"]}}))'
}

# assert_gate <name> <hook-invocation> <command> <expected-exit>
assert_gate() {
  local name="$1" hook="$2" command="$3" want="$4" got
  payload "$command" | bash $hook >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then pass "$name"; else
    echo "    want exit $want, got $got" >&2
    fail "$name"
  fi
}

echo "== prose gate, pr mode =="
assert_gate "a plain create body passes" "$PROSE" \
  "$GH_CREATE --title \"fix(hooks): gate the edit path\" --body \"Adds one check.\"" 0
assert_gate "a blocked word on create is caught" "$PROSE" \
  "$GH_CREATE --body \"A pivotal change.\"" 2
assert_gate "a plain edit body passes" "$PROSE" \
  "$GH_EDIT --body \"Adds one check.\"" 0
assert_gate "a blocked word on edit is caught" "$PROSE" \
  "$GH_EDIT --body \"This will utilize the shared client.\"" 2
assert_gate "an edit with no body passes" "$PROSE" \
  "$GH_EDIT --title \"fix(hooks): a subject\"" 0

echo
echo "== the body reaches the gate in every shape =="
BLOCKED_FILE="$TEST_DIR/blocked-body.md"
printf '## What does this PR do?\n\nThis showcases the new flow.\n' > "$BLOCKED_FILE"
assert_gate "a --body-file body is read" "$PROSE" \
  "$GH_CREATE --body-file $BLOCKED_FILE" 2
assert_gate "a heredoc body is read" "$PROSE" \
  "$GH_CREATE --body <<'PRBODY'
## What does this PR do?

The intricate interplay of modules.
PRBODY" 2

echo
echo "== body gate, attribution =="
assert_gate "a clean body passes" "$BODY" \
  "$GH_CREATE --title \"fix(hooks): gate the edit path\" --body \"Adds one check.\"" 0
assert_gate "a co-author trailer blocks" "$BODY" \
  "$GH_CREATE --body \"Adds one check.

Co-Authored-By: Someone <someone@example.com>\"" 2
assert_gate "an attribution footer blocks" "$BODY" \
  "$GH_CREATE --body \"Adds one check. Generated with Claude Code\"" 2
assert_gate "an attribution footer on edit blocks" "$BODY" \
  "$GH_EDIT --body \"Adds one check. Generated with Codex\"" 2
assert_gate "a robot emoji blocks" "$BODY" \
  "$GH_CREATE --body \"Adds one check. 🤖\"" 2
assert_gate "attribution in the title blocks" "$BODY" \
  "$GH_CREATE --title \"fix: a subject (Generated with Claude)\" --body \"Adds one check.\"" 2
assert_gate "a build tool that generates output passes" "$BODY" \
  "$GH_CREATE --body \"The policy file is generated with a script.\"" 0

echo
echo "== body gate, local state paths =="
assert_gate "a state path blocks" "$BODY" \
  "$GH_CREATE --body \"Implements .claude/state/plans/2026-09-16-gates.md\"" 2
assert_gate "a state path on edit blocks" "$BODY" \
  "$GH_EDIT --body \"See .claude/state/research/2026-09-16-gates.md\"" 2
STATE_FILE="$TEST_DIR/state-body.md"
printf '## What does this PR do?\n\n- Follows .claude/state/plans/x.md\n' > "$STATE_FILE"
assert_gate "a state path in a --body-file blocks" "$BODY" \
  "$GH_CREATE --body-file $STATE_FILE" 2

echo
echo "== plumbing =="
assert_gate "an unrelated command is skipped" "$BODY" "npm test" 0
assert_gate "the create help flag is skipped" "$BODY" "$GH_CREATE --help" 0
assert_gate "the edit help flag is skipped" "$BODY" "gh ""pr edit --help" 0
assert_gate "an unrelated command is skipped by the prose gate" "$PROSE" "npm test" 0

echo ""
echo "$PASSED passed; $FAILED failed"
[ "$FAILED" -eq 0 ]
