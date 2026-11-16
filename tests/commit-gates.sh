#!/bin/bash
# Tests for the PreToolUse commit gates: the message gate's conventional
# format and co-author trailer checks, and the commit mode of the prose gate.
#
# The gates read the message from the command string, so only a heredoc or
# -m value belonging to the commit call counts. A heredoc earlier in the
# chain, such as a PR body written to a file, is someone else's prose.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
GATE="$PROJECT_DIR/hooks/pre-commit-msg-gate.sh"
CONVENTIONAL="$GATE"
COAUTHOR="$GATE"
PROSE="$PROJECT_DIR/hooks/prose-gate.sh"
# Assembled so this file never carries the literal phrase the hooks trigger on.
GIT_COMMIT="git ""commit"
GIT_C="git"" -C"

# assert_gate <name> <hook-invocation> <command> <expected-exit>
assert_gate() { expect_exit "$1" "$4" run_gate "$2" "$3"; }
# shellcheck disable=SC2086  # the invocation carries the hook's mode argument
run_gate() { payload "$2" | bash $1; }

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

assert_gate "--help is skipped" "$CONVENTIONAL" "$GIT_COMMIT --help" 0
assert_gate "a real commit chained before a help call is still checked" "$CONVENTIONAL" \
  "$GIT_COMMIT -m \"just some words\" && $GIT_COMMIT --help" 2
assert_gate "a message that mentions -h is still checked" "$CONVENTIONAL" \
  "$GIT_COMMIT -m \"pass -h to see usage\"" 2

echo
echo "== global options between git and commit =="
assert_gate "a quoted git -C commit is checked" "$CONVENTIONAL" \
  "$GIT_C \"/tmp/a b\" commit -m \"just some words\"" 2
assert_gate "a quoted git -C conventional commit passes" "$CONVENTIONAL" \
  "$GIT_C \"/tmp/a b\" commit -m \"fix: a subject\"" 0
assert_gate "git -c before commit is checked" "$CONVENTIONAL" \
  "git -c user.name=x commit -m \"just some words\"" 2
assert_gate "git --no-pager before commit is checked" "$CONVENTIONAL" \
  "git --no-pager commit -m \"just some words\"" 2
assert_gate "git -C is not read as commit -C" "$CONVENTIONAL" \
  "$GIT_COMMIT -m \"just some words\" && $GIT_C ../other push" 2
assert_gate "commit -C after git -C reuses the message" "$CONVENTIONAL" \
  "$GIT_C /tmp/x commit -C HEAD~1" 0
assert_gate "a quoted mention of the commit command is not a commit" "$CONVENTIONAL" \
  "echo \"$GIT_COMMIT -m 'just some words'\"" 0
assert_gate "a git -C heredoc message is read" "$CONVENTIONAL" \
  "$GIT_C /tmp/x commit -F- <<'MSG'
not a conventional subject
MSG" 2

echo
echo "== is_conventional =="
# shellcheck source=../hooks/lib/commit-msg.sh
. "$PROJECT_DIR/hooks/lib/commit-msg.sh"
check "every listed type passes" is_conventional "revert(api)!: undo it"
check "a type outside CONVENTIONAL_TYPES fails" not is_conventional "feature: add it"
check "a missing description fails" not is_conventional "fix: "

echo
echo "== co-author trailer =="
assert_gate "a co-author trailer blocks" "$COAUTHOR" \
  "$GIT_COMMIT -m \"fix: x

Co-Authored-By: A <a@example.com>\"" 2
assert_gate "a co-author trailer behind git -C blocks" "$COAUTHOR" \
  "$GIT_C \"/tmp/a b\" commit -m \"fix: x

co-authored-by: A <a@example.com>\"" 2
assert_gate "a commit without a trailer passes" "$COAUTHOR" "$GIT_COMMIT -m \"fix: x\"" 0
assert_gate "a non-commit command is skipped" "$COAUTHOR" "echo \"Co-Authored-By: A\"" 0
assert_gate "a commit checks only the trailer, not the PR footer rules" "$COAUTHOR" \
  "$GIT_COMMIT -m \"fix: x

Generated with Claude Code\"" 0
TRAILER="$GIT_COMMIT -m \"just some words

Co-Authored-By: A <a@example.com>\""
check "the trailer bypass leaves the subject check on" \
  [ "$(payload "$TRAILER" | SKIP_COAUTHOR_GATE=1 bash "$GATE" >/dev/null 2>&1; echo $?)" = 2 ]
check "the subject bypass leaves the trailer check on" \
  [ "$(payload "$TRAILER" | SKIP_CONVENTIONAL_GATE=1 bash "$GATE" >/dev/null 2>&1; echo $?)" = 2 ]
check "both bypasses let the commit through" \
  [ "$(payload "$TRAILER" | SKIP_COAUTHOR_GATE=1 SKIP_CONVENTIONAL_GATE=1 bash "$GATE" >/dev/null 2>&1; echo $?)" = 0 ]

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
assert_gate "a blocked word behind git -C is caught" "$PROSE commit" \
  'git -C . commit -m "fix(x): utilize the thing"' 2
assert_gate "git -C commit --help is not linted" "$PROSE commit" \
  'git -C . commit --help' 0
assert_gate "a blocked word in a real heredoc is caught" "$PROSE commit" \
  "$GIT_COMMIT -F- <<'MSG'
fix(x): a fine subject

This body will utilize a blocked word.
MSG" 2

echo
echo "== one run per tool call =="
harness_init once ONCE_TMP
BLOCKED="$GIT_COMMIT -m \"fix(x): utilize the thing\""

# once_exit <tool_use_id> <mode> [tmpdir]: exit code of the prose gate on BLOCKED.
once_exit() {
  COMMAND="$BLOCKED" ID="$1" python3 -c 'import json,os; print(json.dumps({"hook_event_name":"PreToolUse","tool_use_id":os.environ["ID"],"tool_input":{"command":os.environ["COMMAND"]}}))' \
    | TMPDIR="${3:-$ONCE_TMP}" bash "$PROSE" "$2" >/dev/null 2>&1
  echo $?
}

check_once() {
  if [ "$1" = "$2" ]; then pass "$3"; else
    echo "    want $2, got $1" >&2
    fail "$3"
  fi
}

check_once "$(once_exit toolu_a commit) $(once_exit toolu_a commit)" "2 0" \
  "a second registration on the same tool call defers to the first run"
check_once "$(once_exit toolu_b commit)" "2" "another tool call runs the gate again"
check_once "$(once_exit toolu_d pr) $(once_exit toolu_d commit)" "0 2" "a claim by another mode does not skip this one"
check_once "$(payload "$BLOCKED" | TMPDIR="$ONCE_TMP" bash "$PROSE" commit >/dev/null 2>&1; echo $?) $(payload "$BLOCKED" | TMPDIR="$ONCE_TMP" bash "$PROSE" commit >/dev/null 2>&1; echo $?)" "2 2" \
  "a payload without a tool_use_id runs every time"
chmod 500 "$ONCE_TMP"
check_once "$(once_exit toolu_c commit "$ONCE_TMP/missing")" "2" "an unwritable claim dir still runs the gate"
chmod 700 "$ONCE_TMP"

# A new worktree's husky hooks are restored before its first commit, so git
# runs pre-commit and commit-msg for it.
BRANCH_GATE="$PROJECT_DIR/hooks/pre-commit-branch-gate.sh"
MAIN="$ONCE_TMP/husky-main"
LINKED="$ONCE_TMP/husky-linked"
git init -q "$MAIN"
mkdir -p "$MAIN/.husky/_"
printf '#!/bin/sh\nexit 0\n' > "$MAIN/.husky/_/pre-commit"
chmod +x "$MAIN/.husky/_/pre-commit"
printf '.husky/_\n' > "$MAIN/.gitignore"
git -C "$MAIN" config core.hooksPath .husky/_
git -C "$MAIN" add -A
git -C "$MAIN" -c user.name=t -c user.email=t@t commit -qm init --no-verify
git -C "$MAIN" worktree add -q -b feature/husky "$LINKED" >/dev/null 2>&1
payload "git commit -m 'fix: x'" "$LINKED" \
  | (cd "$ONCE_TMP" && SKIP_COMMIT_BRANCH_GATE=1 bash "$BRANCH_GATE" >/dev/null 2>&1)
if [ -x "$LINKED/.husky/_/pre-commit" ]; then
  pass "the commit gate restores a new worktree's husky hooks, bypass or not"
else
  fail "the commit gate restores a new worktree's husky hooks, bypass or not"
fi

finish
