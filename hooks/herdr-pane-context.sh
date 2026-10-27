#!/bin/bash
# SessionStart, CwdChanged, and Stop hook: report the pane's repo, branch, and
# worktree to herdr as $repo, $branch, and $wt sidebar tokens, plus one of
# $c0..$c13 as a color marker that the herdr config styles.
# Stop is included because a branch switch inside a session fires no event.
# A fresh session start also sorts the agent panel by repo, because herdr
# drops the agent view on server restart.
# Always exits 0; never blocks.

set -u

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v herdr >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null || true)
dir=""
event_source=""
if command -v jq >/dev/null 2>&1; then
  dir=$(printf '%s' "$input" | jq -r '.new_cwd // .cwd // empty' 2>/dev/null || true)
  event_source=$(printf '%s' "$input" | jq -r 'select(.hook_event_name == "SessionStart") | .source // empty' 2>/dev/null || true)
fi
[ -n "$dir" ] && [ -d "$dir" ] || dir="$PWD"

source_id="agent-config:pane-context"

if [ "$event_source" = "startup" ] && [ -S "${HERDR_SOCKET_PATH:-}" ] && command -v python3 >/dev/null 2>&1; then
  python3 - "$HERDR_SOCKET_PATH" <<'PY_VIEW' >/dev/null 2>&1 || true
import json, socket, sys
request = {"id": "agent-config:repo-view", "method": "agent.view.set", "params": {
    "source": "agent-config:repo-groups", "label": "by repo", "sort": [
        {"field": "workspace_order", "order": "asc"},
        {"field": {"token": "repo"}, "order": "asc"},
        {"field": "tab_order", "order": "asc"},
        {"field": "pane_order", "order": "asc"}]}}
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
    client.settimeout(0.5)
    client.connect(sys.argv[1])
    client.sendall((json.dumps(request) + "\n").encode())
    try:
        client.recv(4096)
    except socket.timeout:
        pass
PY_VIEW
fi

colors=14
clear_colors=()
for i in $(seq 0 $((colors - 1))); do clear_colors+=(--clear-token "c$i"); done

if ! git_dir=$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null); then
  herdr pane report-metadata "$HERDR_PANE_ID" --source "$source_id" \
    --clear-token repo --clear-token branch --clear-token wt "${clear_colors[@]}" >/dev/null 2>&1 || true
  exit 0
fi

common_dir=$(cd "$dir" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
# The first worktree entry is the main checkout, also for submodules and bare repos.
main_wt=$(git -C "$dir" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
repo=$(basename "${main_wt:-$(dirname "$common_dir")}" .git)
branch=$(git -C "$dir" branch --show-current 2>/dev/null)
[ -n "$branch" ] || branch=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo "?")

# Each new repo takes the lowest color unused in its space, so the first 14
# repos of a space never share one. Spaces are keyed by label, which survives restarts.
space=$(herdr workspace get "${HERDR_PANE_ID%%:*}" 2>/dev/null | jq -r '.result.workspace.label // empty' 2>/dev/null)
space=${space// /_}
color_file="${XDG_STATE_HOME:-$HOME/.local/state}/herdr/repo-colors"
mkdir -p "$(dirname "$color_file")"
touch "$color_file"
color=$(awk -v s="${space:-_}" -v r="$repo" '$1 == s && $2 == r { print $3; exit }' "$color_file")
if [ -z "$color" ]; then
  color=$(awk -v s="${space:-_}" -v n="$colors" '$1 == s { used[$3] = 1; count++ } END { for (i = 0; i < n; i++) if (!(i in used)) { print i; exit } print count % n }' "$color_file")
  printf '%s %s %s\n' "${space:-_}" "$repo" "$color" >>"$color_file"
fi
color_args=()
for i in $(seq 0 $((colors - 1))); do
  if [ "$i" = "$color" ]; then color_args+=(--token "c$i=●"); else color_args+=(--clear-token "c$i"); fi
done

if [ "$(cd "$git_dir" && pwd -P)" = "$common_dir" ]; then
  wt_args=(--clear-token wt)
else
  wt_args=(--token "wt=⎇ $(basename "$(git -C "$dir" rev-parse --show-toplevel)")")
fi

herdr pane report-metadata "$HERDR_PANE_ID" --source "$source_id" \
  --token "repo=$repo" --token "branch=$branch" "${wt_args[@]}" "${color_args[@]}" >/dev/null 2>&1 || true
exit 0
