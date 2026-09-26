#!/bin/bash
# Tests for hooks/pre-pr-test-gate.sh.
#
# A repo declaring `verify` opens a PR only when <git-dir>/verify-passed holds
# HEAD and the tree is clean; the hook never runs the suite itself. The repo
# comes from a leading `cd`, not the payload cwd, so a hub session opening a
# sibling repo's PR checks the sibling. Every create also checks the title.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$PROJECT_DIR/hooks/pre-pr-test-gate.sh"
# Assembled so this file never carries the literal phrases the hooks trigger on.
GH_CREATE="gh ""pr create"
GH_READY="gh ""pr ready"
TMP_ROOT=$(cd "${TMPDIR:-/tmp}" && pwd)
TEST_ROOT=$(cd "$(mktemp -d "$TMP_ROOT/pre-pr-test-gate-test.XXXXXX")" && pwd)
PASSED=0
FAILED=0

cleanup() {
  case "$TEST_ROOT" in
    "$TMP_ROOT"/pre-pr-test-gate-test.*) rm -rf "$TEST_ROOT" ;;
    *) echo "Refusing to clean unexpected test path: $TEST_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

pass() { PASSED=$((PASSED + 1)); echo "ok - $1"; }
fail() { FAILED=$((FAILED + 1)); echo "not ok - $1" >&2; }

# The verify and test scripts both fail, so a pass proves the hook ran neither.
make_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  cat > "$dir/package.json" <<'JSON'
{ "name": "probe", "private": true, "scripts": { "verify": "exit 1", "test": "exit 1" } }
JSON
  git -C "$dir" add package.json
  git -C "$dir" -c user.name=t -c user.email=t@example.com commit -qm "chore: init"
}

stamp() { git -C "$1" rev-parse HEAD > "$(git -C "$1" rev-parse --path-format=absolute --git-dir)/verify-passed"; }

# assert_gate <name> <payload-cwd> <command> <expected-exit> [expected-output]
assert_gate() {
  local name="$1" cwd="$2" command="$3" want="$4" want_out="${5:-}" out got
  out=$(CWD="$cwd" COMMAND="$command" python3 -c \
    'import json,os; print(json.dumps({"cwd":os.environ["CWD"],"tool_input":{"command":os.environ["COMMAND"]}}))' \
    | (cd "$TEST_ROOT" && CLAUDE_PROJECT_DIR="" SKIP_PR_TEST_GATE="" bash "$HOOK" 2>&1))
  got=$?
  if [ "$got" -eq "$want" ] && { [ -z "$want_out" ] || printf '%s' "$out" | grep -qF -- "$want_out"; }; then
    pass "$name"
  else
    echo "    want exit $want, got $got: $out" >&2
    fail "$name"
  fi
}

REPO="$TEST_ROOT/repo"
HUB="$TEST_ROOT/hub"
make_repo "$REPO"
mkdir -p "$HUB"
printf '{ "name": "hub", "private": true, "scripts": { "test": "exit 0" } }\n' > "$HUB/package.json"
TITLE='--title "feat(api): add a thing" --body "Adds it."'

echo "== verify stamp =="
assert_gate "no stamp blocks and says how to verify" "$REPO" "$GH_CREATE $TITLE" 2 "npm run verify"
stamp "$REPO"
assert_gate "a stamp at HEAD with a clean tree passes" "$REPO" "$GH_CREATE $TITLE" 0
assert_gate "ready reads the same stamp" "$REPO" "$GH_READY 12" 0
touch "$REPO/dirty"
assert_gate "a dirty tree blocks" "$REPO" "$GH_CREATE $TITLE" 2 "npm run verify"
rm "$REPO/dirty"
git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m "fix: move head"
assert_gate "a stamp for an older commit blocks" "$REPO" "$GH_READY 12" 2 "npm run verify"
assert_gate "a draft create skips the stamp" "$REPO" "$GH_CREATE --draft $TITLE" 0
assert_gate "ready --undo is not gated" "$REPO" "$GH_READY 12 --undo" 0

echo
echo "== repo resolution =="
assert_gate "a leading cd beats a hub payload cwd" "$HUB" "cd $REPO && $GH_CREATE $TITLE" 2 "$REPO"
stamp "$REPO"
assert_gate "a stamped sibling passes from the hub" "$HUB" "cd $REPO && $GH_CREATE $TITLE" 0

echo
echo "== title =="
assert_gate "a non-conventional title blocks" "$REPO" "$GH_CREATE --title \"Add a thing\" --body \"x\"" 2 "conventional commit"
assert_gate "an unknown type blocks" "$REPO" "$GH_CREATE -t \"feature: add a thing\" --body \"x\"" 2 "conventional commit"
assert_gate "a breaking-change title passes" "$REPO" "$GH_CREATE --title 'feat(api)!: drop v1' --body \"x\"" 0
assert_gate "no title flag is left to gh" "$REPO" "$GH_CREATE --fill" 0
assert_gate "a title the shell expands is left to CI" "$REPO" "$GH_CREATE --title \"\$TITLE\" --body \"x\"" 0
assert_gate "a command-substitution title is left to CI" "$REPO" "$GH_CREATE --title \"\$(cat title.txt)\" --body \"x\"" 0
assert_gate "a single-quoted dollar title is still checked" "$REPO" "$GH_CREATE --title 'Add a \$5 fee' --body \"x\"" 2 "conventional commit"
assert_gate "a -t inside the body is not read as the title" "$REPO" "$GH_CREATE --body \"run it with -t 'x'\" --title \"feat: add a thing\"" 0

echo
echo "== fallback without verify =="
assert_gate "a repo without verify runs npm test" "$HUB" "$GH_CREATE $TITLE" 0 "All tests passed"
assert_gate "an unrelated command is skipped" "$REPO" "npm test" 0

echo ""
echo "$PASSED passed; $FAILED failed"
[ "$FAILED" -eq 0 ]
