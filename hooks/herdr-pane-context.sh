#!/bin/bash
# SessionStart, CwdChanged, and Stop hook: report the pane's repo, branch, and
# worktree to herdr as $repo, $icon, $branch, and $wt sidebar tokens.
# Stop is included because a branch switch inside a session fires no event.
# SessionStart also sorts the agent panel by repo, because herdr drops the
# agent view on server restart.
# Always exits 0; never blocks.

set -u

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v herdr >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null || true)
dir=""
event=""
if command -v jq >/dev/null 2>&1; then
  dir=$(printf '%s' "$input" | jq -r '.new_cwd // .cwd // empty' 2>/dev/null || true)
  event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null || true)
fi
[ -n "$dir" ] && [ -d "$dir" ] || dir="$PWD"

source_id="agent-config:pane-context"

if [ "$event" = "SessionStart" ] && [ -S "${HERDR_SOCKET_PATH:-}" ] && command -v nc >/dev/null 2>&1; then
  printf '%s\n' '{"id":"agent-config:repo-view","method":"agent.view.set","params":{"source":"agent-config:repo-groups","label":"by repo","sort":[{"field":"workspace_order","order":"asc"},{"field":{"token":"repo"},"order":"asc"},{"field":"tab_order","order":"asc"},{"field":"pane_order","order":"asc"}]}}' |
    nc -U -w 2 "$HERDR_SOCKET_PATH" >/dev/null 2>&1 || true
fi

if ! git_dir=$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null); then
  herdr pane report-metadata "$HERDR_PANE_ID" --source "$source_id" \
    --clear-token repo --clear-token icon --clear-token branch --clear-token wt >/dev/null 2>&1 || true
  exit 0
fi

common_dir=$(cd "$dir" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
# The first worktree entry is the main checkout, also for submodules and bare repos.
main_wt=$(git -C "$dir" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
repo=$(basename "${main_wt:-$(dirname "$common_dir")}" .git)
branch=$(git -C "$dir" branch --show-current 2>/dev/null)
[ -n "$branch" ] || branch=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo "?")

# A stable color per repo name, so panes of one repo share a marker.
icons=(🔴 🟠 🟡 🟢 🔵 🟣 🟤 ⚪)
sum=$(printf '%s' "$repo" | cksum | cut -d' ' -f1)
icon=${icons[$((sum % ${#icons[@]}))]}

if [ "$(cd "$git_dir" && pwd -P)" = "$common_dir" ]; then
  wt_args=(--clear-token wt)
else
  wt_args=(--token "wt=⎇ $(basename "$(git -C "$dir" rev-parse --show-toplevel)")")
fi

herdr pane report-metadata "$HERDR_PANE_ID" --source "$source_id" \
  --token "repo=$repo" --token "icon=$icon" --token "branch=$branch" "${wt_args[@]}" >/dev/null 2>&1 || true
exit 0
