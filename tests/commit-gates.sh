#!/bin/bash
# Tests for the PreToolUse commit gates: conventional format, and the commit
# mode of the prose gate.
#
# Both extract the message from the command string, and both used to take the
# first heredoc anywhere in it. A command that writes a PR body and then
# commits therefore had someone elses prose read as its commit subject.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
CONVENTIONAL="$PROJECT_DIR/hooks/pre-commit-conventional-gate.sh"
PROSE="$PROJECT_DIR/hooks/prose-gate.sh"
# Assembled so this file never carries the literal phrase the hooks trigger on.
GIT_COMMIT="git ""commit"
PASSED=0
FAILED=0

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

echo "== conventional format =="
assert_gate "a conventional subject passes" "$CONVENTIONAL" \
  "$GIT_COMMIT -m \"fix(hooks): repair the thing\"" 0
assert_gate "a non-conventional subject blocks" "$CONVENTIONAL" \
  "$GIT_COMMIT -m \"just some words\"" 2
assert_gate "an unknown type blocks" "$CONVENTIONAL" \
  "$GIT_COMMIT -m \"wibble: a subject\"" 2
assert_gate "a scoped breaking change passes" "$CONVENTIONAL" \
  "$GIT_COMMIT -m \"feat(api)!: drop v1\"" 0
assert_gate "amend is skipped" "$CONVENTIONAL" \
  "$GIT_COMMIT --amend --no-edit" 0
assert_gate "a merge subject is skipped" "$CONVENTIONAL" \
  "$GIT_COMMIT -m \"Merge branch main\"" 0

echo
echo "== the message comes from this command, not an unrelated heredoc =="
UNRELATED="cat > /tmp/body.md <<'BODY'
## What does this PR do?
Prose that is not a commit subject.
BODY
$GIT_COMMIT -m \"fix(hooks): a valid subject\""
assert_gate "an unrelated heredoc does not become the subject" "$CONVENTIONAL" "$UNRELATED" 0
assert_gate "an unrelated heredoc is not linted as the message" "$PROSE commit" "$UNRELATED" 0

REAL_HEREDOC="$GIT_COMMIT -F- <<'MSG'
not a conventional subject

body
MSG"
assert_gate "a real heredoc message is still read" "$CONVENTIONAL" "$REAL_HEREDOC" 2

echo
echo "== prose gate, commit mode =="
assert_gate "a plain message passes" "$PROSE commit" \
  "$GIT_COMMIT -m \"fix(hooks): read the payload cwd\"" 0
assert_gate "a blocked word is caught" "$PROSE commit" \
  "$GIT_COMMIT -m \"fix(x): utilize the thing\"" 2
assert_gate "a blocked word in a real heredoc is caught" "$PROSE commit" \
  "$GIT_COMMIT -F- <<'MSG'
fix(x): a fine subject

This body will utilize a blocked word.
MSG" 2

echo ""
echo "$PASSED passed; $FAILED failed"
[ "$FAILED" -eq 0 ]
