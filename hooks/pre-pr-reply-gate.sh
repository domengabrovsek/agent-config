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
# A `gh api` comment sent through --input, a GraphQL comment or reply
# mutation, or an in_reply_to the shell expands also blocks, because the gate
# cannot read its footer or parent. Other GraphQL calls pass.
#
# Exit 2 blocks the action and feeds the message back to the agent.
# Bypass the footer check with SKIP_REPLY_FOOTER=1.

# shellcheck source=lib/resolve-repo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/resolve-repo.sh"
# shellcheck source=lib/pr-body.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/pr-body.sh"
# shellcheck source=lib/once.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/once.sh"

INPUT=$(cat)
first_run_for_call "$INPUT" pre-pr-reply-gate || exit 0
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
# The body is free text, so a `git -C <dir>` inside it must not pick the repo.
REPO_CMD=${COMMAND%%body=*}
for flag in --body -b -F; do REPO_CMD=${REPO_CMD%%[[:space:]]"$flag"[[:space:]=]*}; done
DIR=$(resolve_repo_dir "$REPO_CMD" "$CWD")

# block <line>...: prints each line with the gate prefix on the first and exits 2.
block() {
  echo "[pre-pr-reply-gate] $1" >&2
  shift
  for line in "$@"; do echo "$line" >&2; done
  exit 2
}

if [ "$KIND" = api ]; then
  # Flags sit before the first body= field; the body itself is free text.
  FLAGS=${COMMAND%%body=*}
  COMMENT_ENDPOINT='(issues|pulls)/([0-9]+/(comments|reviews)|comments/[0-9]+)|commits/[0-9a-f]+/comments'

  if printf '%s\n' "$FLAGS" | grep -qE '(^|[[:space:]])graphql([[:space:]]|$)'; then
    # A query the shell builds, such as query="$(cat q.graphql)", hides the mutation.
    if printf '%s\n' "$COMMAND" | grep -qE 'query="?[$`]'; then
      block "Cannot read a GraphQL query the shell builds." \
        "Pass the query inline in single quotes, or with -F query=@<file>, so the gate can check it."
    fi
    # A query or --input file holds the mutation the call sends, so read it too.
    GQL="$COMMAND"
    while IFS= read -r f; do
      if [ "$f" = - ] || ! GQL="$GQL $(cd "$DIR" 2>/dev/null && cat -- "$f")"; then
        block "Cannot read the GraphQL document in $f." \
          "Pass the query inline in single quotes, or with -F query=@<file>, so the gate can check it."
      fi
    done < <(printf '%s\n' "$COMMAND" \
      | grep -oE '(query=@|--input[= ]+)[^[:space:]"'\'']+' | sed -E 's/^(query=@|--input[= ]+)//')
    if printf '%s\n' "$GQL" | grep -qE '(addPullRequestReviewThreadReply|addPullRequestReviewComment|addPullRequestReviewThread|addComment|updateIssueComment|updatePullRequestReviewComment)([^A-Za-z]|$)' \
      || { printf '%s\n' "$GQL" | grep -qE '(addPullRequestReview|submitPullRequestReview)([^A-Za-z]|$)' \
        && printf '%s\n' "$GQL" | grep -qE '(^|[^A-Za-z])body([^A-Za-z]|$)'; }; then
      block "Refusing a GraphQL comment or reply mutation: the gate cannot check its footer or parent." \
        "Post it through the REST endpoint, such as: gh api repos/{owner}/{repo}/pulls/<n>/comments/<id>/replies -f body='...'"
    fi
    exit 0
  fi

  if printf '%s\n' "$FLAGS" | grep -qE '(^|[[:space:]])--input([= ]|$)' \
    && printf '%s\n' "$FLAGS" | grep -qE "$COMMENT_ENDPOINT"; then
    block "Refusing a comment sent with --input: the gate cannot check its footer or parent." \
      "Pass the body with -f body='...' or -F body=@<file>, and in_reply_to as a literal number."
  fi

  # Every in_reply_to counts, so a later one in the body cannot stand in for the real parent.
  PARENTS=""
  while IFS= read -r value; do
    case "$value" in
      ''|*[!0-9]*)
        block "Cannot check the parent of in_reply_to=$value." \
          "Write the parent comment ID as a literal number, such as -F in_reply_to=123456." ;;
    esac
    PARENTS="$PARENTS $value"
  done < <(printf '%s\n' "$COMMAND" \
    | grep -oE 'in_reply_to(_id)?=["'\'']?[^[:space:]"'\'']*' | sed -E 's/^in_reply_to(_id)?=["'\'']?//')
  # The first match is the endpoint; a later one sits in the free-text body.
  PARENTS="$(printf '%s\n' "$COMMAND" | grep -oE 'pulls/[0-9]+/comments/[0-9]+/replies' | head -1 \
    | sed -E 's#pulls/[0-9]+/comments/([0-9]+)/replies#\1#')$PARENTS"
  # PR, issue, and release bodies also travel as body=, and they must not
  # carry the footer, so only comment and review endpoints count.
  if [ -z "${PARENTS// /}" ] && ! { printf '%s\n' "$COMMAND" | grep -qE "$COMMENT_ENDPOINT" \
    && printf '%s\n' "$COMMAND" | grep -qE '(-f|-F|--field|--raw-field)[= ]+["'\'']?body='; }; then
    exit 0
  fi

  for PARENT in $PARENTS; do
    REPO=$(printf '%s\n' "$COMMAND" | grep -oE 'repos/[{}A-Za-z0-9_.-]+/[{}A-Za-z0-9_.-]+/pulls/' | head -1 \
      | sed -E 's#repos/(.*)/pulls/#\1#')
    REPO=${REPO:-"{owner}/{repo}"}

    CLASS=$(cd "$DIR" 2>/dev/null && gh api "repos/$REPO/pulls/comments/$PARENT" \
      --jq 'if .user.type == "Bot" or (.user.login | endswith("[bot]")) then "bot" else "human:" + .user.login end' 2>/dev/null)

    case "$CLASS" in
      bot) ;;
      human:*)
        block "Refusing to reply to ${CLASS#human:}, a human reviewer." \
          "Write the reply as a draft and give it to the user to post." ;;
      *)
        block "Could not resolve the author of comment $PARENT." \
          "Check the comment ID and gh auth, then retry." ;;
    esac
  done
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
  BODY=$(cd "$DIR" 2>/dev/null && extract_api_body "$COMMAND")
fi

# A "$(cat <<EOF ... EOF)" body ends with the heredoc close, so unwrap it
# before checking what the body ends with. The footer needs a blank line
# above it, or GitHub renders it inline at the end of the last sentence.
if ! printf '%s' "$BODY" | python3 -c '
import re, sys
body = sys.stdin.read().strip()
h = re.match(r"\$\(cat <<-?[\x27\"]?(\w+)[\x27\"]?\n(.*)\n\s*\1\s*\)$", body, re.S)
if h:
    body = h.group(2).strip()
sys.exit(0 if re.search(r"\n[ \t]*\n<sub>Posted by [^<]+ on behalf of @[A-Za-z0-9-]+</sub>$", body) else 1)
'; then
  echo "[pre-pr-reply-gate] This comment posts under the user's account without the agent footer on its own line." >&2
  echo "End the body with a blank line, then: <sub>Posted by <agent> on behalf of @<login></sub>" >&2
  echo "Write the body inline or in a file; a body built from a variable cannot be checked." >&2
  echo "(Bypass: SKIP_REPLY_FOOTER=1)" >&2
  exit 2
fi

exit 0
