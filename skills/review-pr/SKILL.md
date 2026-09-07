---
name: review-pr
description: "Reviews a pull request with structured severity-based feedback. Use when asked to review a PR, asked for a code review, or given a PR number/URL."
---

Review the pull request: $ARGUMENTS

Follow this process:

**why-no-hook:** review workflow guidance; each step requires reading the PR and judging code quality / intent.

1. **Fetch PR details**: run `gh pr view $ARGUMENTS --json title,body,files,commits,additions,deletions,baseRefName,headRefName` `(review-time: see section note)`
2. **Read the diff**: run `gh pr diff $ARGUMENTS` to see all changes `(review-time: see section note)`
3. **Understand intent**: read the PR description, linked issues, and commit messages before reviewing code `(review-time: see section note)`
4. **Spec-conformance pass** (when a spec exists): find the originating spec - issue refs in the commits (via `gh`), a linked issue, or a spec under `.claude/state/specs/` - and check the diff against it, ideally in a parallel sub-agent so it does not pollute the main review context: (a) requirements asked for but missing or partial; (b) behaviour in the diff nobody asked for (scope creep); (c) requirements that look implemented but wrong. Quote the spec line for each finding and place it in the severity buckets below. If there is no spec, skip this pass and note it. `(review-time: see section note)`
5. **Load relevant agents**: based on the files changed, load the appropriate expert agents from `~/.agents/agents/` for domain-specific review `(review-time: see section note)`
6. **Review systematically** using the checklist in @checklist.md `(review-time: see section note)`
7. **Produce structured output** in this format: `(review-time: see section note)`

```markdown
## Summary

<1-2 sentence overall assessment>

## Verdict: APPROVE / REQUEST_CHANGES / NEEDS_DISCUSSION

<reason>

## Findings

### BLOCKER (must fix before merge)

- **[file:line]** - Description. Why it matters. Suggested fix.

### ISSUE (should fix, may approve with commitment to follow-up)

- **[file:line]** - Description. Recommendation.

### SUGGESTION (take it or leave it)

- **[file:line]** - Description. Alternative approach.

### NIT (style/preference, non-blocking)

- **[file:line]** - Description.

### PRAISE (good patterns worth highlighting)

- **[file:line]** - What's done well and why.
```

If no `$ARGUMENTS` provided, review changes in the current branch against the base branch using `git diff main...HEAD`.
