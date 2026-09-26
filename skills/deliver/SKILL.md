---
name: deliver
description: "Deliver a feature end to end with one human gate: you approve the spec, then the agent plans, builds tests-first, verifies against the spec, opens the PR, and drives CI and review comments until it is ready to merge."
disable-model-invocation: true
---

# Deliver

Deliver: $ARGUMENTS

An orchestrator. You approve the spec. Everything after that runs without asking, except the gates listed below. The run keeps its state in `.claude/state/runs/<branch-slug>/tasks.md`, so it survives compaction and a resumed session.

## Stages

**why-no-hook:** skill workflow guidance; each step requires understanding the surrounding context (repo, task shape, prior state).

1. **Research**: run `/research` when the code is unfamiliar. Skip it for code already read this session `(review-time: see section note)`
2. **Spec**: run `/spec`. Discovery asks one question at a time. The spec's Open Questions must be empty before you approve it. Notify with `~/.agents/scripts/notify.sh "Spec ready for review"` `(review-time: see section note)`
3. **Set up**, after approval: `(review-time: see section note)`
   - Create the branch and worktree with `/worktree <slug>`, and set the spec's `branch:` frontmatter `(review-time: see section note)`
   - Write `tasks.md` with one line per stage, and tick stages as they finish `(review-time: see section note)`
   - Print this line for the user to paste as `/goal`, which keeps the session working across turns: `The PR for <spec> is open, CI is green, every automated criterion passes at HEAD, and no bot comment is unanswered.` The run continues without it `(review-time: see section note)`
4. **Plan**: run `/plan`. It asks only about an architectural choice the spec left open `(review-time: see section note)`
5. **Build**: run `/build`, which runs each slice through its Slice Loop. A plan spanning two or more repos goes to `/drive-fleet` with the plan instead `(review-time: see section note)`
6. **Verify**: spawn the `Spec Verifier` for the whole branch, then run `/verify-done`. Fix and repeat until both pass `(review-time: see section note)`
7. **Open the PR**: run `/mr`. It reuses the step 6 pass when nothing changed since. List manual criteria under **Blocked on me** in the PR body `(review-time: see section note)`
8. **Watch**: run `/ci` and `/pr-comments` until CI is green and every bot comment has a reply. Human-reviewer replies go to the user as drafts `(review-time: see section note)`
9. **Report**: end with **Blocked on me**, **Changed**, and **Found**, plus the PR URL. Notify with `~/.agents/scripts/notify.sh "PR ready: <url>"` `(review-time: see section note)`

## Gates the user keeps

Stop and ask only for these `(review-time: see section note)`:

- Approving the spec
- Posting a reply to a human reviewer
- Force-pushing, merging, or pushing to `main`
- Deploying or applying to production
- Deleting data, or changing anything outside the repository and its PR

## Budget and escalation

- Three review rounds per slice, from `/build` `(review-time: see section note)`
- Three attempts at the same CI failure, from `/ci` `(review-time: see section note)`
- The same failure twice on any other step `(review-time: see section note)`
- A finding or conflict that invalidates the plan: update the plan, and ask only if the scope changes `(review-time: see section note)`

On escalation, notify, add the item under **Blocked on me** in `tasks.md`, and keep working on slices that do not depend on it `(review-time: see section note)`
