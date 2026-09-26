#!/bin/bash
# Pre-PR reply gate: guards comments the agent posts under the user's account.
#
# Two checks:
#   human reply  blocks an inline reply to a review comment written by a human.
#                The agent replies to bots itself; a human reviewer's reply
#                goes to the user as a draft, per skills/pr-comments.
#   footer       every comment the agent posts ends with the agent footer, so
#                the user can tell it apart from their own comments.
#
# PreToolUse hook on Bash. A comment is `gh pr comment`, `gh issue comment`, or
# a `gh api` call that posts a body. A reply is the replies endpoint
# (pulls/<n>/comments/<id>/replies) or a new comment carrying in_reply_to. The
# parent author is looked up with gh; a failed lookup blocks, because a wrongly
# blocked bot reply is cheap and a post to a human cannot be taken back.
#
# Exit 2 blocks the action and feeds the message back to the agent.
# Bypass the footer check with SKIP_REPLY_FOOTER=1.

# shellcheck source=lib/resolve-repo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/resolve-repo.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

case "$COMMAND" in
  *"gh pr comment --help"*|*"gh pr comment -h"*|*"gh issue comment --help"*|*"gh issue comment -h"*) exit 0 ;;
  *"gh pr comment"*|*"gh issue comment"*) KIND=cli ;;
  *"gh api"*) KIND=api ;;
  *) exit 0 ;;
esac

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
DIR=$(resolve_repo_dir "$COMMAND" "$CWD")

if [ "$KIND" = api ]; then
  PARENT=$(printf '%s\n' "$COMMAND" \
    | sed -nE 's#.*pulls/[0-9]+/comments/([0-9]+)/replies.*#\1#p' | head -1)
  if [ -z "$PARENT" ]; then
    PARENT=$(printf '%s\n' "$COMMAND" \
      | sed -nE 's#.*in_reply_to(_id)?=([0-9]+).*#\2#p' | head -1)
  fi
  # A gh api call without a parent or a body field reads, not posts.
  if [ -z "$PARENT" ] && ! printf '%s\n' "$COMMAND" | grep -qE '(-f|-F|--field|--raw-field)[= ]+body='; then
    exit 0
  fi

  if [ -n "$PARENT" ]; then
    REPO=$(printf '%s\n' "$COMMAND" \
      | sed -nE 's#.*repos/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pulls/.*#\1#p' | head -1)
    case "$REPO" in
      ""|"{owner}/{repo}") REPO="{owner}/{repo}" ;;
    esac

    CLASS=$(cd "$DIR" 2>/dev/null && gh api "repos/$REPO/pulls/comments/$PARENT" \
      --jq 'if .user.type == "Bot" or (.user.login | endswith("[bot]")) then "bot" else "human:" + .user.login end' 2>/dev/null)

    case "$CLASS" in
      bot) ;;
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
  fi
  BODY_FILE=$(printf '%s\n' "$COMMAND" \
    | sed -nE "s#.*(-F|--field)[= ]+body=@([^ '\"]+).*#\2#p" | head -1)
else
  BODY_FILE=$(printf '%s\n' "$COMMAND" \
    | sed -nE "s#.*(--body-file|-F)[= ]+['\"]?([^ '\"]+).*#\2#p" | head -1)
fi

[ "$SKIP_REPLY_FOOTER" = "1" ] && exit 0

# A body read from a file never appears in the command, so check both.
HAYSTACK="$COMMAND"
if [ -n "$BODY_FILE" ] && [ "$BODY_FILE" != "-" ]; then
  case "$BODY_FILE" in
    /*) ;;
    *) BODY_FILE="$DIR/$BODY_FILE" ;;
  esac
  [ -f "$BODY_FILE" ] && HAYSTACK=$(printf '%s\n%s' "$COMMAND" "$(cat "$BODY_FILE")")
fi

if ! printf '%s' "$HAYSTACK" | grep -qE '<sub>Posted by [^<]+ on behalf of @[A-Za-z0-9-]+</sub>'; then
  echo "[pre-pr-reply-gate] This comment posts under the user's account without the agent footer." >&2
  echo "End the body with: <sub>Posted by <agent> on behalf of @<login></sub>" >&2
  echo "(Bypass: SKIP_REPLY_FOOTER=1)" >&2
  exit 2
fi

exit 0
