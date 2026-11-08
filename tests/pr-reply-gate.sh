#!/bin/bash
# Tests for hooks/pre-pr-reply-gate.sh. A stub gh on PATH answers the parent
# comment lookup: 111 is a bot, 222 is a human, 333 fails. Every comment the
# agent posts must also end with the agent footer.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
GATE="$PROJECT_DIR/hooks/pre-pr-reply-gate.sh"

harness_init pr-reply-gate TEST_DIR

stub "$TEST_DIR/bin" gh <<'STUB'
#!/bin/bash
case "$*" in
  *repos/other/*) exit 1 ;;
  *pulls/comments/111*) echo "bot" ;;
  *pulls/comments/222*) echo "human:alice" ;;
  *) exit 1 ;;
esac
STUB
export PATH="$TEST_DIR/bin:$PATH"

# assert_gate <name> <command> <expected-exit>
assert_gate() {
  local name="$1" command="$2" want="$3" got
  payload "$command" "$TEST_DIR" | bash "$GATE" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then pass "$name"; else
    echo "    want exit $want, got $got" >&2
    fail "$name"
  fi
}

GH_API="gh ""api"
GH_PR_COMMENT="gh ""pr comment"
GH_ISSUE_COMMENT="gh ""issue comment"
SIGNATURE="<sub>Posted by Claude Code on behalf of @owner</sub>"
FOOTER=$'\n\n'"$SIGNATURE"

echo "== human replies =="
assert_gate "a reply to a bot passes" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments/111/replies -f body=\"Fixed in abc123. $FOOTER\"" 0
assert_gate "a reply to a human is blocked" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments/222/replies -f body=\"Done. $FOOTER\"" 2
assert_gate "an in_reply_to comment to a human is blocked" \
  "$GH_API repos/acme/app/pulls/7/comments -F in_reply_to=222 -f body=\"Done. $FOOTER\"" 2
assert_gate "an in_reply_to comment to a bot passes" \
  "$GH_API repos/acme/app/pulls/7/comments -F in_reply_to=111 -f body=\"Done. $FOOTER\"" 0
assert_gate "a failed author lookup blocks" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments/333/replies -f body=\"Done. $FOOTER\"" 2
assert_gate "a git -C path inside a bot reply body does not pick the repo" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments/111/replies -f body=\"Run git -C $TEST_DIR/missing push. $FOOTER\"" 0
assert_gate "a git -C path inside a PR comment body does not pick the repo" \
  "$GH_PR_COMMENT 7 --body \"Run git -C $TEST_DIR/missing push. $FOOTER\"" 0
assert_gate "a repos path inside a reply body does not pick the repo" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments/111/replies -f body=\"See repos/other/thing/pulls/3. $FOOTER\"" 0
assert_gate "a reply path inside a reply body does not pick the parent" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments/111/replies -f body=\"Like pulls/7/comments/222/replies. $FOOTER\"" 0
assert_gate "a read-only gh api call passes" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments" 0
assert_gate "an unrelated command passes" \
  "git status" 0

echo
echo "== footer =="
assert_gate "a bot reply without the footer is blocked" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments/111/replies -f body=\"Fixed in abc123.\"" 2
assert_gate "a new api comment without the footer is blocked" \
  "$GH_API repos/acme/app/issues/7/comments -f body=\"Done.\"" 2
assert_gate "a PR comment with the footer passes" \
  "$GH_PR_COMMENT 7 --body \"Done. $FOOTER\"" 0
assert_gate "a PR comment without the footer is blocked" \
  "$GH_PR_COMMENT 7 --body \"Done.\"" 2
assert_gate "an issue comment without the footer is blocked" \
  "$GH_ISSUE_COMMENT 7 -b \"Done.\"" 2
printf 'Done.\n\n%s\n' "$FOOTER" > "$TEST_DIR/reply.md"
assert_gate "a body file with the footer passes" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments/111/replies -F body=@reply.md" 0
assert_gate "a --body-file with the footer passes" \
  "$GH_PR_COMMENT 7 --body-file reply.md" 0
printf 'Done.\n' > "$TEST_DIR/bare.md"
assert_gate "a --body-file without the footer is blocked" \
  "$GH_PR_COMMENT 7 --body-file bare.md" 2
if payload "$GH_PR_COMMENT 7 --body \"Done.\"" "$TEST_DIR" | SKIP_REPLY_FOOTER=1 bash "$GATE" >/dev/null 2>&1; then
  pass "SKIP_REPLY_FOOTER lets a comment through"
else
  fail "SKIP_REPLY_FOOTER lets a comment through"
fi
assert_gate "help is not gated" \
  "$GH_PR_COMMENT --help" 0
assert_gate "a footer outside the body does not count" \
  "echo \"$FOOTER\" && $GH_PR_COMMENT 7 --body \"Done.\"" 2
assert_gate "a footer on the same line as the text is blocked" \
  "$GH_PR_COMMENT 7 --body \"Done. $SIGNATURE\"" 2
assert_gate "a footer on the next line without a blank line is blocked" \
  "$GH_PR_COMMENT 7 --body \"Done.
$SIGNATURE\"" 2
assert_gate "a footer before the end does not count" \
  "$GH_PR_COMMENT 7 --body \"$FOOTER Done.\"" 2
assert_gate "a heredoc body ending in the footer passes" \
  "$GH_PR_COMMENT 7 --body \"\$(cat <<'EOF'
Done.

$FOOTER
EOF
)\"" 0
assert_gate "an unparsed body flag is checked, not skipped" \
  "$GH_PR_COMMENT 7 --body Done" 2
assert_gate "a -F body file with the footer passes" \
  "$GH_PR_COMMENT 7 -F reply.md" 0

echo
echo "== reviews =="
GH_PR_REVIEW="gh ""pr review"
assert_gate "a review comment without the footer is blocked" \
  "$GH_PR_REVIEW 7 --comment -b \"Looks off.\"" 2
assert_gate "a review comment with the footer passes" \
  "$GH_PR_REVIEW 7 --request-changes -b \"Looks off. $FOOTER\"" 0
assert_gate "an approval without a body passes" \
  "$GH_PR_REVIEW 7 --approve" 0

echo
echo "== calls the gate cannot read =="
printf '{"body": "Done."}\n' > "$TEST_DIR/reply.json"
assert_gate "a comment sent with --input is blocked" \
  "$GH_API repos/acme/app/pulls/1/comments --input reply.json" 2
assert_gate "a reply sent with --input is blocked" \
  "$GH_API repos/acme/app/pulls/1/comments/111/replies --input=reply.json" 2
assert_gate "a variable in_reply_to is blocked" \
  "$GH_API repos/acme/app/pulls/7/comments -F in_reply_to=\$ID -f body=\"Done. $FOOTER\"" 2
assert_gate "a quoted variable in_reply_to is blocked" \
  "$GH_API repos/acme/app/pulls/7/comments -F \"in_reply_to=\${ID}\" -f body=\"Done. $FOOTER\"" 2
assert_gate "a bot in_reply_to in the body does not hide a human parent" \
  "$GH_API repos/acme/app/pulls/7/comments -F in_reply_to=222 -f body=\"See in_reply_to=111. $FOOTER\"" 2
assert_gate "a quoted body field still gets the footer check" \
  "$GH_API repos/acme/app/issues/7/comments -f \"body=Done.\"" 2
assert_gate "a quoted body field with the footer passes" \
  "$GH_API repos/acme/app/issues/7/comments -f \"body=Done. $FOOTER\"" 0
assert_gate "a stdin heredoc body with the footer passes" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments/111/replies -F body=@- <<'EOF'
Done.

$SIGNATURE
EOF" 0
assert_gate "a stdin heredoc body without the footer is blocked" \
  "$GH_API repos/{owner}/{repo}/pulls/7/comments/111/replies -F body=@- <<'EOF'
Done.
EOF" 2
assert_gate "a GraphQL thread reply is blocked" \
  "$GH_API graphql -f query='mutation{addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:\"x\",body:\"Done. $FOOTER\"}){comment{id}}}'" 2
assert_gate "a GraphQL review comment is blocked" \
  "$GH_API graphql -f query='mutation{addPullRequestReviewComment(input:{body:\"x\"}){clientMutationId}}'" 2
assert_gate "a GraphQL issue comment is blocked" \
  "$GH_API graphql -f query='mutation(\$id:ID!,\$b:String!){addComment(input:{subjectId:\$id,body:\$b}){clientMutationId}}' -f id=x -f b=y" 2
assert_gate "a GraphQL review with a body is blocked" \
  "$GH_API graphql -f query='mutation{addPullRequestReview(input:{pullRequestId:\"x\",event:COMMENT,body:\"y\"}){clientMutationId}}'" 2
assert_gate "a GraphQL approval without a body passes" \
  "$GH_API graphql -f query='mutation{addPullRequestReview(input:{pullRequestId:\"x\",event:APPROVE}){clientMutationId}}'" 0
printf 'mutation{addComment(input:{subjectId:"x",body:"y"}){clientMutationId}}\n' > "$TEST_DIR/comment.graphql"
assert_gate "a GraphQL comment read from a query file is blocked" \
  "$GH_API graphql -F query=@comment.graphql" 2
assert_gate "a GraphQL query the shell builds is blocked" \
  "$GH_API graphql -f query=\"\$(cat comment.graphql)\"" 2
assert_gate "a GraphQL comment read from a quoted --input file is blocked" \
  "$GH_API graphql --input \"comment.graphql\"" 2
assert_gate "a GraphQL comment read from a quoted query file is blocked" \
  "$GH_API graphql -F query=@'comment.graphql'" 2
assert_gate "a GraphQL --input path the shell builds is blocked" \
  "$GH_API graphql --input \"\$F\"" 2
printf 'query{viewer{login}}\n' > "$TEST_DIR/viewer.graphql"
assert_gate "a GraphQL query read from a quoted file passes" \
  "$GH_API graphql --input \"viewer.graphql\"" 0
assert_gate "a GraphQL document read from stdin is blocked" \
  "$GH_API graphql --input -" 2
assert_gate "a GraphQL comment sent to a quoted endpoint is blocked" \
  "$GH_API 'graphql' -f query='mutation{addComment(input:{subjectId:\"x\",body:\"y\"}){clientMutationId}}'" 2
assert_gate "a GraphQL comment sent to /graphql is blocked" \
  "$GH_API /graphql -f query='mutation{addComment(input:{subjectId:\"x\",body:\"y\"}){clientMutationId}}'" 2
assert_gate "a GraphQL review body edit is blocked" \
  "$GH_API graphql -f query='mutation{updatePullRequestReview(input:{pullRequestReviewId:\"x\",body:\"y\"}){clientMutationId}}'" 2
assert_gate "a GraphQL thread resolve passes" \
  "$GH_API graphql -f query='mutation{resolveReviewThread(input:{threadId:\"x\"}){thread{id}}}'" 0
assert_gate "a GraphQL query passes" \
  "$GH_API graphql -f query='query{viewer{login}}'" 0

echo
echo "== bodies that are not comments =="
assert_gate "a PR body posted through gh api passes" \
  "$GH_API repos/acme/app/pulls -f title=\"feat: x\" -f body=\"Adds x.\"" 0
assert_gate "a PR body edit through gh api passes" \
  "$GH_API -X PATCH repos/acme/app/pulls/7 -f body=\"Adds x.\"" 0
assert_gate "a release body passes" \
  "$GH_API repos/acme/app/releases -f tag_name=v1 -f body=\"Notes.\"" 0

finish
