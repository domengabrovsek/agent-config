#!/bin/bash
# Pre-PR gate: block opening a PR, or marking one ready, before the repo's
# checks pass, and block a PR title that is not a conventional commit.
# Runs as a PreToolUse hook on Bash(gh pr create *) and Bash(gh pr ready *).
# Exit code 2 blocks the action and sends the error message to Claude.
#
# A repo that declares a `verify` script records each full pass by writing
# HEAD to `<git-dir>/verify-passed`. This hook only reads that stamp: the full
# run takes minutes, longer than a hook may block. A draft PR skips the stamp
# check, because `gh pr ready` checks it before anyone reviews.
# A repo without `verify` gets `npm test` on create, run here.
#
# Bypass with SKIP_PR_TEST_GATE=1.

# shellcheck source=lib/resolve-repo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/resolve-repo.sh"
# shellcheck source=lib/pr-body.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/pr-body.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

case "$COMMAND" in
  *"gh pr create --help"*|*"gh pr create -h"*) exit 0 ;;
  *"gh pr ready --help"*|*"gh pr ready -h"*|*"gh pr ready"*"--undo"*) exit 0 ;;
  *"gh pr create"*) ACTION=create ;;
  *"gh pr ready"*) ACTION=ready ;;
  *) exit 0 ;;
esac

[ "$SKIP_PR_TEST_GATE" = "1" ] && exit 0

# The CI title check (amannn/action-semantic-pull-request) uses these types.
if [ "$ACTION" = create ]; then
  TITLE=$(extract_pr_title "$COMMAND")
  if [ -n "$TITLE" ] && ! printf '%s' "$TITLE" \
    | grep -qE '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^)]+\))?!?: .+'; then
    echo "[pre-pr-test-gate] The PR title is not a conventional commit, so the CI title check would fail." >&2
    echo "Title: $TITLE" >&2
    echo "Expected: <type>(<scope>)?!?: <subject>, type one of feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert" >&2
    exit 2
  fi
fi

# A `cd <repo> &&` prefix moves the command away from the payload cwd, which
# is where a hub or sibling session started.
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
DIR=$(resolve_repo_dir "$COMMAND" "$CWD")

PROJECT_ROOT=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  [ -f "$DIR/package.json" ] && PROJECT_ROOT="$DIR" && break
  DIR=$(dirname "$DIR")
done

# No package.json - skip (not a JS/TS project)
[ -z "$PROJECT_ROOT" ] && exit 0

cd "$PROJECT_ROOT" || exit 0

has_script() {
  node -e "const p=require('./package.json'); process.exit(p.scripts?.['$1'] ? 0 : 1)" 2>/dev/null
}

if has_script verify; then
  if [ "$ACTION" = create ]; then
    case " $COMMAND " in
      *" --draft "*|*" -d "*) exit 0 ;;
    esac
  fi
  STAMP="$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)/verify-passed"
  HEAD_SHA=$(git rev-parse HEAD 2>/dev/null)
  if [ -n "$HEAD_SHA" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$HEAD_SHA" ] \
    && [ -z "$(git status --porcelain 2>/dev/null)" ]; then
    echo "[pre-pr-test-gate] npm run verify passed at HEAD $HEAD_SHA." >&2
    exit 0
  fi
  echo "[pre-pr-test-gate] $PROJECT_ROOT has no verify pass for HEAD ${HEAD_SHA:-?} with a clean tree." >&2
  echo "Run \`npm run verify\` there (it takes minutes: use run_in_background or a 600000ms timeout), then retry." >&2
  exit 2
fi

# The fallback keeps its create-only scope: `npm test` can outrun a ready hook.
[ "$ACTION" = create ] && has_script test || exit 0

echo "Running tests before PR creation..." >&2
TEST_OUTPUT=$(CI=true npm test 2>&1)
TEST_EXIT=$?

if [ $TEST_EXIT -ne 0 ]; then
  echo "Tests failed - fix before creating PR:" >&2
  echo "$TEST_OUTPUT" | tail -20 >&2
  exit 2
fi

echo "All tests passed." >&2
exit 0
