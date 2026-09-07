#!/bin/bash
# Pre-git PR state refresh.
# Before write-side git/gh commands, probe origin + gh and inject a one-line
# state block as additionalContext so Claude sees ground truth instead of
# inferring from stale conversation memory.
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

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ "$SKIP_PR_STATE_REFRESH" = "1" ] && exit 0

# Match trigger commands only. Anything else exits silently.
case "$COMMAND" in
  *"git push"*) ;;
  *"git commit"*) ;;
  *"gh pr edit"*|*"gh pr comment"*|*"gh pr merge"*) ;;
  *"gh pr close"*|*"gh pr ready"*|*"gh pr review"*) ;;
  *) exit 0 ;;
esac

# --help / -h variants are harmless; skip.
case "$COMMAND" in
  *" --help"*|*" -h"*) exit 0 ;;
esac

emit() {
  # Inject as additionalContext so Claude sees the state line.
  jq -n --arg ctx "$1" '{
    continue: true,
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: $ctx
    }
  }'
  exit 0
}

# The hook's own cwd is not the tool call's, so the repo comes from the
# payload. Reading only CLAUDE_PROJECT_DIR made every probe report
# "unavailable=not-a-repo" whenever the harness ran hooks from elsewhere.
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
DIR=$(resolve_repo_dir "$COMMAND" "$CWD")

# Not in a git repo - nothing to probe.
if ! git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  emit "[pr-state] unavailable=not-a-repo"
fi

BRANCH=$(git -C "$DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
[ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ] && emit "[pr-state] unavailable=detached-head"

# Skip git commit on default branch - the commit-branch-gate already blocks it.
case "$COMMAND" in
  *"git commit"*)
    case "$BRANCH" in
      main|master) exit 0 ;;
    esac
    ;;
esac

# No remote configured - nothing to fetch / no PR to look up.
if ! git -C "$DIR" remote get-url origin >/dev/null 2>&1; then
  emit "[pr-state] branch=$BRANCH unavailable=no-remote"
fi

# Probe origin and gh. Both errors degrade silently to unavailable.
git -C "$DIR" fetch --prune origin >/dev/null 2>&1
PR_JSON=$(gh pr view --json state,mergedAt,headRefName,url 2>/dev/null)

if [ -z "$PR_JSON" ]; then
  emit "[pr-state] branch=$BRANCH state=NONE (no PR for this branch, or gh unavailable)"
fi

STATE=$(echo "$PR_JSON" | jq -r '.state // "UNKNOWN"')
URL=$(echo "$PR_JSON" | jq -r '.url // ""')
MERGED_AT=$(echo "$PR_JSON" | jq -r '.mergedAt // ""')

LINE="[pr-state] branch=$BRANCH state=$STATE url=$URL"
[ -n "$MERGED_AT" ] && [ "$MERGED_AT" != "null" ] && LINE="$LINE mergedAt=$MERGED_AT"

# For merged / closed PRs on action commands, append a suggestion so the model
# pauses and re-evaluates intent.
case "$STATE" in
  MERGED)
    case "$COMMAND" in
      *"git push"*|*"git commit"*)
        LINE="$LINE
SUGGESTION: PR is already merged. If you intended new work, start a fresh branch from the default branch first."
        ;;
      *"gh pr edit"*|*"gh pr comment"*|*"gh pr merge"*|*"gh pr close"*|*"gh pr ready"*|*"gh pr review"*)
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
