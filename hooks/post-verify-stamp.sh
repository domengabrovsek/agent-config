#!/bin/bash
# PostToolUse hook: after a foreground `npm run verify` succeeds on a clean
# tree, write HEAD to <git-dir>/agent-verify-passed. pre-pr-test-gate.sh reads
# that stamp before `gh pr create` and `gh pr ready`.
#
# The name differs from <git-dir>/verify-passed, which a repo's own verify
# script may write from inside the sandbox. Deny rules keep sandboxed commands
# and the Edit and Write tools away from agent-verify-passed, and this hook
# runs outside the sandbox, so only it can write the stamp the gate trusts.
#
# PostToolUse fires only when the Bash call exits 0, so success is the exit
# code of the whole command. The command must therefore be `npm run verify`
# alone: a pipe, a `;` or `||` would report another command's exit code, and
# a background run reports success when it starts, not when it ends. Only a
# leading `cd <dir> &&` and trailing output redirections are allowed around
# it. A redirect must point outside the repo or at an ignored path: an
# untracked log file makes the tree dirty.
#
# A VAR=value prefix, an npm_config_* setting or --ignore-scripts leaves no
# stamp, because npm_config_script_shell=/usr/bin/true or a skipped script
# exits 0 without running verify.
#
# Always exits 0. Bypass with SKIP_VERIFY_STAMP=1.

[ "${SKIP_VERIFY_STAMP:-}" = "1" ] && exit 0

# shellcheck source=lib/resolve-repo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/resolve-repo.sh"
# shellcheck source=lib/find-up.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/find-up.sh"
# shellcheck source=lib/package-json.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/package-json.sh"
# shellcheck source=lib/context.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/context.sh"
# shellcheck source=lib/hook.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/hook.sh"

hook_read

case "$COMMAND" in
  *"npm run verify"*) ;;
  *) exit 0 ;;
esac

# no_stamp <reason>: say why a verify run left no stamp, so the agent re-runs
# the right shape instead of finding out at `gh pr create`. verify:fast and
# other verify:* scripts never stamp and get no note.
no_stamp() {
  if printf '%s\n' "$COMMAND" | grep -qE 'npm run verify([[:space:]]|$)'; then
    emit_context PostToolUse "[verify-stamp] No verify stamp: $1. Run \`cd <repo> && npm run verify\` alone, in the foreground, on a clean tree."
  fi
  exit 0
}

printf '%s\n' "$COMMAND" | grep -qiE 'npm_config_|--ignore-scripts' && no_stamp "npm_config_* and --ignore-scripts can skip the script"
[ "$(echo "$INPUT" | jq -r '.tool_input.run_in_background // false')" = "true" ] && no_stamp "a background run has not finished when it starts"
# A foreground run that outlives the Bash timeout moves to the background and
# reports success at that moment, before verify has finished.
[ -n "$(echo "$INPUT" | jq -r '.tool_response.backgroundTaskId // empty')" ] && no_stamp "the run moved to the background before it finished"
[ "$(echo "$INPUT" | jq -r '.tool_response.interrupted // false')" = "true" ] && no_stamp "the run was interrupted"

CORE="$COMMAND"
case "$CORE" in
  "cd "*"&&"*)
    # Only a single `cd <path>`: a `;` before the `&&` would stamp the wrong repo.
    PREFIX=${CORE%%"&&"*}
    printf '%s\n' "$PREFIX" | grep -qE '^cd[[:space:]]+[^[:space:];|&]+[[:space:]]*$' || no_stamp "only a single \`cd <dir> &&\` may come before it"
    CORE=${CORE#*&&}
    ;;
esac
CORE=$(printf '%s\n' "$CORE" | sed -E \
  -e 's/^[[:space:]]+//' \
  -e ':redir' -e 's/[[:space:]]+[0-9]?(>>?|>&)[[:space:]]*[^[:space:]&|;]+[[:space:]]*$//' -e 't redir' \
  -e 's/[[:space:]]+$//')
[ "$CORE" = "npm run verify" ] || no_stamp "anything besides \`npm run verify\` and a trailing redirect can hide or fake the exit code"

DIR=$(resolve_repo_dir "$COMMAND" "$CWD")
# The PostToolUse cwd may already be the cd target, so a relative cd path resolves twice.
[ -d "$DIR" ] || [ -z "$CWD" ] || DIR="$CWD"
# npm runs the script from the nearest package.json, as pre-pr-test-gate.sh reads it.
PACKAGE=$(find_up "$DIR" package.json) || exit 0
DIR=$(dirname "$PACKAGE")
cd "$DIR" || exit 0

has_script verify || exit 0

GIT_DIR=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
HEAD_SHA=$(git rev-parse HEAD 2>/dev/null) || exit 0
[ -z "$(git status --porcelain 2>/dev/null)" ] || no_stamp "the tree has uncommitted or untracked files"

printf '%s\n' "$HEAD_SHA" > "$GIT_DIR/agent-verify-passed" || exit 0

emit_context PostToolUse "[verify-stamp] Recorded a verify pass for HEAD $HEAD_SHA in $DIR."
exit 0
