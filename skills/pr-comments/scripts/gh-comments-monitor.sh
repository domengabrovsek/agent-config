#!/usr/bin/env bash
# Monitor a GitHub PR for new reviewer comments.
# Usage: gh-comments-monitor.sh [--repo <path>] [pr-number]
#   --repo   a checkout or worktree of the PR's repo (default: the cwd)
#   pr-number defaults to that checkout's branch PR
# Emits one line per new comment:
#   comment|<inline|review|conversation>|<id>|<author>|<bot|human>|<url>
# Exits when the PR is merged or closed.
set -uo pipefail

repo="" pr=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,/^[^#]/s/^# \{0,1\}//p' "$0"; exit 0 ;;
    --repo)
      [ $# -ge 2 ] || { echo "error|no-repo|"; exit 1; }
      repo="$2"; shift 2 ;;
    *) pr="$1"; shift ;;
  esac
done
if [ -n "$repo" ] && ! cd "$repo" 2>/dev/null; then
  echo "error|no-repo|$repo"
  exit 1
fi

pr="${pr:-$(gh pr view --json number --jq '.number' 2>/dev/null)}"
branch=$(git branch --show-current)
if [ -z "$pr" ]; then
  echo "no-pr|$branch"
  exit 0
fi

interval="${PR_COMMENTS_INTERVAL:-60}"
me=$(gh api user --jq '.login' 2>/dev/null) || me=""

# Seen IDs persist across Monitor re-arms, so a restart never re-emits a comment.
# They live under the main checkout, as rules/state-persistence.md requires.
main=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
state_dir="$main/.claude/state/runs/${branch//\//-}"
seen="$state_dir/comments-seen"
mkdir -p "$state_dir"
touch "$seen"

classify='(if .user.type == "Bot" or (.user.login | endswith("[bot]")) then "bot" else "human" end)'

list_comments() {
  gh api --paginate "repos/{owner}/{repo}/pulls/$pr/comments" \
    --jq ".[] | \"inline|\(.id)|\(.user.login)|\($classify)|\(.html_url)\"" || return 1
  gh api --paginate "repos/{owner}/{repo}/pulls/$pr/reviews" \
    --jq ".[] | select(.state != \"PENDING\" and (.body // \"\") != \"\") | \"review|\(.id)|\(.user.login)|\($classify)|\(.html_url)\"" || return 1
  gh api --paginate "repos/{owner}/{repo}/issues/$pr/comments" \
    --jq ".[] | \"conversation|\(.id)|\(.user.login)|\($classify)|\(.html_url)\"" || return 1
}

error_count=0
while true; do
  state=$(gh pr view "$pr" --json state --jq '.state' 2>/dev/null) || state=""
  if lines=$(list_comments 2>/dev/null) && [ -n "$state" ]; then
    error_count=0
  else
    error_count=$((error_count + 1))
    if [ "$error_count" -ge 5 ]; then
      echo "error|persistent-failure"
      exit 1
    fi
    sleep "$interval"
    continue
  fi

  while IFS='|' read -r kind id author class url; do
    [ -z "$id" ] && continue
    [ "$author" = "$me" ] && continue
    grep -qx "$kind:$id" "$seen" && continue
    echo "$kind:$id" >> "$seen"
    echo "comment|$kind|$id|$author|$class|$url"
  done <<< "$lines"

  case "$state" in
    MERGED|CLOSED)
      echo "pr-closed|$state"
      exit 0
      ;;
  esac
  sleep "$interval"
done
