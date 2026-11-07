#!/bin/bash
# Pre-git PR state refresh.
# Before write-side git/gh commands, ask gh for the branch's PR and inject a
# one-line state block as additionalContext so Claude sees ground truth
# instead of inferring from stale conversation memory.
#
# Triggers (regex on the bash command):
#   - git push
#   - git commit (skipped when current branch is main/master)
#   - gh pr (edit|comment|merge|close|ready|review)
#
# Always exit 0. Warn-only; never blocks.
# Bypass with SKIP_PR_STATE_REFRESH=1.

# shellcheck source=lib/resolve-repo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/resolve-repo.sh"
# shellcheck source=lib/context.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/context.sh"
# shellcheck source=lib/once.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/once.sh"

INPUT=$(cat)
first_run_for_call "$INPUT" pre-git-state-refresh || exit 0
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ "$SKIP_PR_STATE_REFRESH" = "1" ] && exit 0

# --help / -h variants are harmless; skip.
case "$COMMAND" in
  *" --help"*|*" -h"*) exit 0 ;;
esac

# Match trigger commands only. Anything else exits silently. The hook's own
# cwd is not the tool call's, so the repo comes from the payload.
# CLAUDE_PROJECT_DIR alone is wrong whenever the harness runs hooks from
# another directory.
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
case "$COMMAND" in
  *"gh pr edit"*|*"gh pr comment"*|*"gh pr merge"*) KIND=gh ;;
  *"gh pr close"*|*"gh pr ready"*|*"gh pr review"*) KIND=gh ;;
  *git*) KIND=git ;;
  *) exit 0 ;;
esac
if [ "$KIND" = git ]; then
  parse_git_command "$COMMAND" "$CWD" "push|commit" || exit 0
  KIND=$GIT_SUB
else
  parse_git_command "$COMMAND" "$CWD"
fi
DIR=$GIT_REPO_DIR

emit() {
  emit_context PreToolUse "$1"
  exit 0
}

# Not in a git repo - nothing to probe.
if ! git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  emit "[pr-state] unavailable=not-a-repo"
fi

BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
[ -z "$BRANCH" ] && emit "[pr-state] unavailable=detached-head"

# Skip git commit on default branch - the commit-branch-gate already blocks it.
if [ "$KIND" = commit ]; then
  case "$BRANCH" in
    main|master) exit 0 ;;
  esac
fi

# No remote configured - no PR to look up.
if ! git -C "$DIR" remote get-url origin >/dev/null 2>&1; then
  emit "[pr-state] branch=$BRANCH unavailable=no-remote"
fi

# A branch no remote has seen cannot have a PR, and most calls land here, so
# the gh round trip is skipped. @{push} rather than @{upstream}: a branch
# created from origin/main tracks origin/main before its first push.
if ! git -C "$DIR" rev-parse --verify -q "$BRANCH@{push}" >/dev/null 2>&1 \
  && [ -z "$(git -C "$DIR" for-each-ref --count=1 --format=x "refs/remotes/*/$BRANCH" 2>/dev/null)" ]; then
  emit "[pr-state] branch=$BRANCH state=NONE (branch never pushed)"
fi

# gh errors degrade silently to unavailable. gh has no -C and reads the branch
# from its cwd, so it runs from the resolved repo too.
PR_JSON=$(cd "$DIR" && gh pr view --json state,mergedAt,headRefName,url 2>/dev/null)

if [ -z "$PR_JSON" ]; then
  emit "[pr-state] branch=$BRANCH state=NONE (no PR for this branch, or gh unavailable)"
fi

# One value per line, because an empty field would collapse under a tab split.
{ read -r STATE; read -r URL; read -r MERGED_AT; } \
  < <(echo "$PR_JSON" | jq -r '.state // "UNKNOWN", .url // "", .mergedAt // ""')

LINE="[pr-state] branch=$BRANCH state=$STATE url=$URL"
[ -n "$MERGED_AT" ] && LINE="$LINE mergedAt=$MERGED_AT"

# For merged / closed PRs on action commands, append a suggestion so the model
# pauses and re-evaluates intent.
case "$STATE" in
  MERGED)
    case "$KIND" in
      push|commit)
        LINE="$LINE
SUGGESTION: PR is already merged. If you intended new work, start a fresh branch from the default branch first."
        ;;
      *)
        LINE="$LINE
SUGGESTION: PR is already merged. Confirm with the user before writing to a merged PR."
        ;;
    esac
    ;;
  CLOSED)
    LINE="$LINE
SUGGESTION: PR is closed (not merged). Confirm with the user before acting on it."
    ;;
esac

emit "$LINE"
