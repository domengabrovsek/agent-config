---
name: pr-comments
description: "Watches an open PR for reviewer comments and addresses them: fixes the code, replies inline to bots, and drafts replies to humans for the user to post. Use after opening a PR, when the user says 'address the comments' or 'check the PR comments', or when a reviewer comments."
---

# Address PR Review Comments

Watch and address comments on: $ARGUMENTS (default: the current branch's PR)

## Workflow

**why-no-hook:** skill workflow guidance; each step requires understanding the surrounding context (repo, task shape, prior state).

1. **Start a Monitor** with `bash scripts/gh-comments-monitor.sh [pr-number]`, resolved inside this skill's own directory. Use `timeout_ms: 1800000` and the description "PR comments on <branch-name>" `(review-time: see section note)`
2. **React to each line**: `(review-time: see section note)`
   - `comment|<kind>|<id>|<author>|<bot|human>|<url>`: handle the comment as below
   - Monitor expiry: re-arm the same script. Seen IDs persist, so nothing repeats `(review-time: see section note)`
   - `pr-closed|<state>` or `no-pr|<branch>`: report and stop `(review-time: see section note)`
   - `error|persistent-failure`: report and stop `(review-time: see section note)`
3. **Read the comment and its thread**: `gh api repos/{owner}/{repo}/pulls/comments/<id>` for inline, `.../pulls/<n>/reviews/<id>` for a review, `.../issues/comments/<id>` for conversation `(review-time: see section note)`
4. **Judge it against the code**: valid, partly valid, or not applicable. Check the claim in the source before agreeing or disagreeing `(review-time: see section note)`
5. **Fix valid points**, bot or human: make the change, run `/verify-done`, commit, push. Batch comments that arrive together into one commit when they touch the same code `(review-time: see section note)`
6. **Reply by author type**: `(review-time: see section note)`
   - **Bot**: post the reply yourself. Inline comments get a thread reply: `gh api repos/{owner}/{repo}/pulls/<n>/comments/<id>/replies -f body=...`. A review body or conversation comment gets a conversation comment that quotes the line it answers `(review-time: see section note)`
   - **Human**: never post. Add the draft to `.claude/state/runs/<branch-slug>/reply-drafts.md` with the comment URL, and show the user the URL and the draft. `hooks/pre-pr-reply-gate.sh` blocks inline replies to humans `(hook)`
7. **Update the PR body** with `gh pr edit` when a fix changes what the PR does `(review-time: see section note)`

## Reply voice

Write as the engineer who owns the PR.

- One to three sentences. Name the change and its commit, or the reason for leaving the code as it is `(review-time: see section note)`
- No thanks-openers, no "Great catch", no "You're right", no apologies, no emoji `(review-time: see section note)`
- No AI attribution and no mention of an agent or a tool writing the reply `(review-time: see section note)`
- Disagree with evidence: the file and line, or the test that covers the case `(review-time: see section note)`
- Run `write-plain` on each reply before posting or drafting `(review-time: see section note)`

Examples:

- "Fixed in a1b2c3d. The retry now stops after the third attempt."
- "Leaving this as is. `parseDate` already rejects empty input, see `src/date.ts:42` and the test in `date.test.ts`."

## Rules

- Never resolve a human reviewer's thread. The reviewer resolves it `(review-time: see section note)`
- Never dismiss a review or re-request review without the user asking `(review-time: see section note)`
- A comment asking for a change outside the PR's scope gets a reply naming the follow-up, not a fix `(review-time: see section note)`
- The same bot comment failing the same fix twice escalates to the user `(review-time: see section note)`
