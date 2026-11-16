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
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
PROSE="$PROJECT_DIR/hooks/prose-gate.sh pr"
BODY="$PROJECT_DIR/hooks/pre-pr-body-gate.sh"
# Assembled so this file never carries the literal phrase the hooks trigger on.
GH_CREATE="gh ""pr create"
GH_EDIT="gh ""pr edit 12"

harness_init pr-gates TEST_DIR

# assert_gate <name> <hook-invocation> <command> <expected-exit>
assert_gate() { expect_exit "$1" "$4" run_gate "$2" "$3"; }
# shellcheck disable=SC2086  # the invocation carries the hook's mode argument
run_gate() { payload "$2" | bash $1; }

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
assert_gate "an attribution footer in an issue blocks" "$BODY" \
  "gh ""issue create --title \"Bug\" --body \"Steps. Generated with Claude Code\"" 2
assert_gate "an attribution footer in an issue edit blocks" "$BODY" \
  "gh ""issue edit 7 --body \"Steps. Generated with Codex\"" 2
assert_gate "a clean issue passes" "$BODY" \
  "gh ""issue create --title \"Bug\" --body \"Steps to reproduce.\"" 0

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
assert_gate "a state path in a command chained before the PR passes" "$BODY" \
  "sed -i '' 's/x/y/' .claude/state/plans/x.md && $GH_CREATE --title \"fix: a\" --body \"Adds one check.\"" 0
assert_gate "a state path in a command chained after the PR passes" "$BODY" \
  "$GH_EDIT --body \"Adds one check.\" 2>&1 | tail -1; cat .claude/state/plans/x.md" 0
assert_gate "a state path on the line before the PR passes" "$BODY" \
  "sed -i '' 's/x/y/' .claude/state/plans/x.md
$GH_CREATE --title \"fix: a\" --body \"Adds one check.\"" 0
assert_gate "a state path in a body variable set before the PR blocks" "$BODY" \
  "body=\"Follows .claude/state/plans/x.md\"; $GH_CREATE --title \"fix: a\" --body \"\$body\"" 2
assert_gate "a state path written to a body file in the same command blocks" "$BODY" \
  "printf 'See .claude/state/plans/x.md' > $TEST_DIR/new-body.md && $GH_CREATE --body-file $TEST_DIR/new-body.md" 2
printf 'Adds one check.\n' > "$TEST_DIR/old-body.md"
assert_gate "a state path written over an existing body file blocks" "$BODY" \
  "cat > $TEST_DIR/old-body.md <<'EOF'
See .claude/state/plans/x.md
EOF
$GH_CREATE --body-file $TEST_DIR/old-body.md" 2
assert_gate "an existing body file with a state path elsewhere in the command passes" "$BODY" \
  "cat .claude/state/plans/x.md; $GH_CREATE --body-file $TEST_DIR/old-body.md" 0
assert_gate "a line continuation does not split the call" "$BODY" \
  "$GH_CREATE \\
  --title \"see .claude/state/plans/x.md\" --body ok" 2
printf 'Adds one check.\n\nGenerated with Claude Code\n' > "$TEST_DIR/attr-body.md"
assert_gate "a body file the command also reads is still checked" "$BODY" \
  "cat $TEST_DIR/attr-body.md; $GH_CREATE --title \"fix: a\" --body-file $TEST_DIR/attr-body.md" 2
assert_gate "a hash inside a word does not hide the rest of the call" "$BODY" \
  "$GH_CREATE --head feat#2 --title \"Follows .claude/state/plans/x.md\" --body ok" 2
assert_gate "a state path in a quoted body with a semicolon still blocks" "$BODY" \
  "$GH_CREATE --body \"Done; see .claude/state/plans/x.md\" && echo ok" 2
assert_gate "an attribution title after a chained command still blocks" "$BODY" \
  "cd /tmp && $GH_CREATE --title \"fix: a (Generated with Claude)\" --body \"Adds one check.\"" 2

echo
echo "== plumbing =="
assert_gate "an unrelated command is skipped" "$BODY" "npm test" 0
assert_gate "the create help flag is skipped" "$BODY" "$GH_CREATE --help" 0
assert_gate "the edit help flag is skipped" "$BODY" "gh ""pr edit --help" 0
assert_gate "a --help inside the body is still checked" "$BODY" \
  "$GH_CREATE --title \"fix: a\" --body \"Run it with --help. Generated with Claude Code\"" 2
assert_gate "a quoted help call in an echo does not skip the gate" "$BODY" \
  "echo \"$GH_CREATE --help\"; $GH_CREATE --body \"Generated with Claude Code\"" 2
assert_gate "the prose gate skips a help call" "$PROSE" "$GH_CREATE --help" 0
assert_gate "a real call chained before a help call is still checked" "$BODY" \
  "$GH_CREATE --body \"Generated with Claude Code\" && gh ""pr edit 12 --help" 2
assert_gate "the prose gate checks a call chained before a help call" "$PROSE" \
  "$GH_CREATE --body \"A pivotal change.\" && gh ""pr edit 12 --help" 2
assert_gate "an unrelated command is skipped by the prose gate" "$PROSE" "npm test" 0

finish
