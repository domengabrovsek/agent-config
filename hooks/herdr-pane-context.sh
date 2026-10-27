#!/bin/bash
# SessionStart, CwdChanged, and Stop hook: report the pane's repo, branch, and
# worktree to herdr as $repo, $branch, and $wt sidebar tokens.
# Stop is included because a branch switch inside a session fires no event.
# Always exits 0; never blocks.

set -u

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v herdr >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null || true)
dir=""
if command -v jq >/dev/null 2>&1; then
  dir=$(printf '%s' "$input" | jq -r '.new_cwd // .cwd // empty' 2>/dev/null || true)
fi
[ -n "$dir" ] && [ -d "$dir" ] || dir="$PWD"

source_id="agent-config:pane-context"

if ! git_dir=$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null); then
  herdr pane report-metadata "$HERDR_PANE_ID" --source "$source_id" \
    --clear-token repo --clear-token branch --clear-token wt >/dev/null 2>&1 || true
  exit 0
fi

common_dir=$(cd "$dir" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
repo=$(basename "$(dirname "$common_dir")")
branch=$(git -C "$dir" branch --show-current 2>/dev/null)
[ -n "$branch" ] || branch=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo "?")

if [ "$(cd "$git_dir" && pwd -P)" = "$common_dir" ]; then
  wt_args=(--clear-token wt)
else
  wt_args=(--token "wt=⎇ $(basename "$(git -C "$dir" rev-parse --show-toplevel)")")
fi

herdr pane report-metadata "$HERDR_PANE_ID" --source "$source_id" \
  --token "repo=$repo" --token "branch=$branch" "${wt_args[@]}" >/dev/null 2>&1 || true
exit 0
