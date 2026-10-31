#!/bin/bash
# PostToolUse hook: after a foreground `npm run verify` succeeds on a clean
# tree, write HEAD to <git-dir>/verify-passed. pre-pr-test-gate.sh reads that
# stamp before `gh pr create` and `gh pr ready`.
#
# PostToolUse fires only when the Bash call exits 0, so success is the exit
# code of the whole command. The command must therefore be `npm run verify`
# alone: a pipe, a `;` or `||` would report another command's exit code, and
# a background run reports success when it starts, not when it ends. Only a
# leading `cd <dir> &&`, leading VAR=value assignments and trailing output
# redirections are allowed around it. A redirect must point outside the repo
# or at an ignored path: an untracked log file makes the tree dirty.
#
# Always exits 0. Bypass with SKIP_VERIFY_STAMP=1.

[ "${SKIP_VERIFY_STAMP:-}" = "1" ] && exit 0

# shellcheck source=lib/resolve-repo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/resolve-repo.sh"
# shellcheck source=lib/find-up.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/find-up.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

case "$COMMAND" in
  *"npm run verify"*) ;;
  *) exit 0 ;;
esac

[ "$(echo "$INPUT" | jq -r '.tool_input.run_in_background // false')" = "true" ] && exit 0
[ "$(echo "$INPUT" | jq -r '.tool_response.interrupted // false')" = "true" ] && exit 0

CORE="$COMMAND"
case "$CORE" in
  "cd "*"&&"*)
    # Only a single `cd <path>`: a `;` before the `&&` would stamp the wrong repo.
    PREFIX=${CORE%%"&&"*}
    printf '%s\n' "$PREFIX" | grep -qE '^cd[[:space:]]+[^[:space:];|&]+[[:space:]]*$' || exit 0
    CORE=${CORE#*&&}
    ;;
esac
CORE=$(printf '%s\n' "$CORE" | sed -E \
  -e 's/^[[:space:]]+//' \
  -e ':env' -e 's/^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+//' -e 't env' \
  -e ':redir' -e 's/[[:space:]]+[0-9]?(>>?|>&)[[:space:]]*[^[:space:]&|;]+[[:space:]]*$//' -e 't redir' \
  -e 's/[[:space:]]+$//')
[ "$CORE" = "npm run verify" ] || exit 0

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
DIR=$(resolve_repo_dir "$COMMAND" "$CWD")
# The PostToolUse cwd may already be the cd target, so a relative cd path resolves twice.
[ -d "$DIR" ] || [ -z "$CWD" ] || DIR="$CWD"
# npm runs the script from the nearest package.json, as pre-pr-test-gate.sh reads it.
PACKAGE=$(find_up "$DIR" package.json) || exit 0
DIR=$(dirname "$PACKAGE")
cd "$DIR" || exit 0

node -e "process.exit(require('./package.json').scripts?.verify ? 0 : 1)" 2>/dev/null || exit 0

GIT_DIR=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
HEAD_SHA=$(git rev-parse HEAD 2>/dev/null) || exit 0
[ -z "$(git status --porcelain 2>/dev/null)" ] || exit 0

printf '%s\n' "$HEAD_SHA" > "$GIT_DIR/verify-passed" || exit 0

jq -n --arg ctx "[verify-stamp] Recorded a verify pass for HEAD $HEAD_SHA in $DIR." '{
  continue: true,
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'
exit 0
