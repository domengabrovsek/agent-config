#!/bin/bash
# Pre-PR reply gate: blocks an inline reply to a review comment written by a
# human. The agent replies to bots itself; a human reviewer's reply goes to the
# user as a draft, per skills/pr-comments.
#
# PreToolUse hook on Bash(gh api *). A reply is either the replies endpoint
# (pulls/<n>/comments/<id>/replies) or a new comment carrying in_reply_to.
# The parent author is looked up with gh; a failed lookup blocks, because a
# wrongly blocked bot reply is cheap and a post to a human cannot be taken back.
#
# Exit 2 blocks the action and feeds the message back to the agent.

# shellcheck source=lib/resolve-repo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/resolve-repo.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

case "$COMMAND" in
  *"gh api"*) ;;
  *) exit 0 ;;
esac

PARENT=$(printf '%s\n' "$COMMAND" \
  | sed -nE 's#.*pulls/[0-9]+/comments/([0-9]+)/replies.*#\1#p' | head -1)
if [ -z "$PARENT" ]; then
  PARENT=$(printf '%s\n' "$COMMAND" \
    | sed -nE 's#.*in_reply_to(_id)?=([0-9]+).*#\2#p' | head -1)
fi
[ -z "$PARENT" ] && exit 0

REPO=$(printf '%s\n' "$COMMAND" \
  | sed -nE 's#.*repos/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pulls/.*#\1#p' | head -1)
case "$REPO" in
  ""|"{owner}/{repo}") REPO="{owner}/{repo}" ;;
esac

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
DIR=$(resolve_repo_dir "$COMMAND" "$CWD")

CLASS=$(cd "$DIR" 2>/dev/null && gh api "repos/$REPO/pulls/comments/$PARENT" \
  --jq 'if .user.type == "Bot" or (.user.login | endswith("[bot]")) then "bot" else "human:" + .user.login end' 2>/dev/null)

case "$CLASS" in
  bot) exit 0 ;;
  human:*)
    echo "[pre-pr-reply-gate] Refusing to reply to ${CLASS#human:}, a human reviewer." >&2
    echo "Write the reply as a draft and give it to the user to post." >&2
    exit 2
    ;;
  *)
    echo "[pre-pr-reply-gate] Could not resolve the author of comment $PARENT." >&2
    echo "Check the comment ID and gh auth, then retry." >&2
    exit 2
    ;;
esac
