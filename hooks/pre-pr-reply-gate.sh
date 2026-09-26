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
# PreToolUse hook on Bash. A comment is `gh pr comment`, `gh issue comment`,
# `gh pr review` with a body, or a `gh api` body posted to a comment or review
# endpoint. A reply is the replies endpoint (pulls/<n>/comments/<id>/replies) or
# a new comment carrying in_reply_to. The parent author is looked up with gh; a
# failed lookup blocks, because a wrongly blocked bot reply is cheap and a post
# to a human cannot be taken back.
#
# Exit 2 blocks the action and feeds the message back to the agent.
# Bypass the footer check with SKIP_REPLY_FOOTER=1.

# shellcheck source=lib/resolve-repo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/resolve-repo.sh"
# shellcheck source=lib/pr-body.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/pr-body.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

case "$COMMAND" in
  *"gh pr comment --help"*|*"gh pr comment -h"*) exit 0 ;;
  *"gh issue comment --help"*|*"gh issue comment -h"*) exit 0 ;;
  *"gh pr review --help"*|*"gh pr review -h"*) exit 0 ;;
  *"gh pr comment"*|*"gh issue comment"*|*"gh pr review"*) KIND=cli ;;
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
  # PR, issue, and release bodies also travel as body=, and they must not
  # carry the footer, so only comment and review endpoints count.
  if [ -z "$PARENT" ] && ! { printf '%s\n' "$COMMAND" \
      | grep -qE '(issues|pulls)/([0-9]+/(comments|reviews)|comments/[0-9]+)|commits/[0-9a-f]+/comments' \
    && printf '%s\n' "$COMMAND" | grep -qE '(-f|-F|--field|--raw-field)[= ]+body='; }; then
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
fi

[ "$SKIP_REPLY_FOOTER" = "1" ] && exit 0

# Relative body files resolve against the repo the command runs in.
if [ "$KIND" = cli ]; then
  BODY=$(cd "$DIR" 2>/dev/null && extract_pr_body "$COMMAND")
  # `gh pr review --approve` with no body flag posts no comment text. A body
  # flag the parser could not read still has to pass the check below.
  if [ -z "$BODY" ] && ! printf '%s\n' "$COMMAND" \
    | grep -qE '(^|[[:space:]])(-b|--body|-F|--body-file)([= ]|$)'; then
    exit 0
  fi
else
  BODY=$(cd "$DIR" 2>/dev/null && printf '%s' "$COMMAND" | python3 -c '
import re, sys
cmd = sys.stdin.read()
m = re.search(r"(?:^|\s)(-f|-F|--field|--raw-field)[=\s]+body=(?:([\x27\"])(.*?)\2|(\S+))", cmd, re.S)
if m:
    val = m.group(3) if m.group(2) else m.group(4)
    if m.group(1) in ("-F", "--field") and val.startswith("@"):
        try:
            val = open(val[1:]).read()
        except OSError:
            val = ""
    print(val)
' 2>/dev/null)
fi

# A "$(cat <<EOF ... EOF)" body ends with the heredoc close, so unwrap it
# before checking what the body ends with.
if ! printf '%s' "$BODY" | python3 -c '
import re, sys
body = sys.stdin.read().strip()
h = re.match(r"\$\(cat <<-?[\x27\"]?(\w+)[\x27\"]?\n(.*)\n\s*\1\s*\)$", body, re.S)
if h:
    body = h.group(2).strip()
sys.exit(0 if re.search(r"<sub>Posted by [^<]+ on behalf of @[A-Za-z0-9-]+</sub>$", body) else 1)
'; then
  echo "[pre-pr-reply-gate] This comment posts under the user's account without the agent footer." >&2
  echo "End the body with: <sub>Posted by <agent> on behalf of @<login></sub>" >&2
  echo "Write the body inline or in a file; a body built from a variable cannot be checked." >&2
  echo "(Bypass: SKIP_REPLY_FOOTER=1)" >&2
  exit 2
fi

exit 0
