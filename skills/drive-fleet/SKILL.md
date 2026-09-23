---
name: drive-fleet
description: "Drives a fleet of MRs/PRs to done with a manager loop plus the built-in /goal command, delegating all edit, review, rebase, and conflict work to worktree-isolated domain-expert subagents. Use when the user says 'drive fleet' or 'drive the fleet', has 2+ independent lanes to drive in parallel, or wants a hands-off manager that stops only when the whole fleet is green, reviewed, and rebased."
---

# Drive Fleet

A two-phase workflow for driving a fleet of MRs/PRs to done in parallel with a manager that never touches a working tree. Platform-neutral: all VCS/CI mechanics delegate to `/mr` and `/ci`.

## When to use

**why-no-hook:** skill workflow guidance; each step requires understanding the surrounding context (repo, task shape, prior state).

- 2+ independent lanes / multiple MRs, often across sibling repos `(review-time: see section note)`
- You want a hands-off MANAGER that delegates every edit and only stops when the whole fleet is done `(review-time: see section note)`
- Not for single-MR work - use `/build` + `/mr` directly `(review-time: see section note)`

## The goal condition

The built-in `/goal` command keeps the session working across turns until the condition holds, then auto-clears. Set it once, in the MANAGER session - it is session-scoped and resets on resume, so a re-planned session re-sets it.

Template (fill the `{knobs}`):

> Every open MR/PR from `{plan}` is CI-green, reviewed (`{review_depth}` applied via review-pr), and rebased on `{target_branch}`. `{post_completion_action}`

| Knob | Default |
| --- | --- |
| `target_branch` | `main` |
| `review_depth` | blockers + majors + one-line fixes |
| `post_completion_action` | none (repo-specific; e.g. "Once all hold simultaneously, trigger the `notify_reviewers` job on each") |

## Phase 1 - Plan via grills

1. Run `/grill-with-docs` (add `grill-me` if you have it installed) to pressure-test the approach against the existing domain model, sharpen terminology, and emit CONTEXT.md terms inline. `(review-time: see section note)`
2. Output: an execution plan in `.claude/state/plans/` that defines the lanes / MRs and **proves they are file-isolated** - no two lanes touch the same file. `(review-time: see section note)`

The plan is the contract. Approving it and setting the `/goal` is your batched authorization for the fleet (see [orchestration.md](orchestration.md)).

## Phase 2 - Drive with /goal (manager-only)

Phase 2 is started by **you, the operator** - the agent cannot open its own session or set its own goal:

1. Open a **fresh** Claude Code session. The plan on disk is the whole handoff; nothing from the grill carries over. This boundary is also a deliberate gate - a long autonomous run should not start as a side effect of planning. `(review-time: see section note)`
2. Type `/goal <condition>` (built into Claude Code). With auto mode on, `/goal` is what keeps the **one** manager session working turn after turn until the fleet meets the condition, then auto-clears. `(review-time: see section note)`
3. Invoke this skill and run the manager loop (see [orchestration.md](orchestration.md)). `(review-time: see section note)`

This stays a **single, thin manager session** the whole time - it never spawns nested sessions. Its context stays small because all editing / review / rebase / conflict work goes to subagents (each with its own context window) and worktrees; the harness compacts the manager's context as it grows. The main loop manages and nothing else - it never edits, reviews, rebases, or resolves conflicts.

> If this skill is invoked with no `/goal` set, stop and ask the operator to set one (ideally in a fresh session) before running the loop.

## Example - a fleet spanning three repos

**Phase 1** (planning session) - describe the work; the agent grills and plans:

```text
/drive-fleet
Add a feature-flag system end-to-end: the evaluation service in the api repo,
the React hook + toggle UI in the web repo, and the shared flag schema in the
shared-types repo. Plan file-isolated lanes across the three repos.
```

The agent runs `/grill-with-docs`, proves the lanes share no files, writes the plan to `.claude/state/plans/`, and hands back the `/goal` line to use next.

**Phase 2** (fresh session) - set the goal, turn on auto mode, start the loop:

```text
/goal Every open MR/PR from the feature-flags plan is CI-green, reviewed
(blockers + majors + one-line fixes via review-pr), and rebased on main.
```

```text
/drive-fleet
Execute the plan at .claude/state/plans/2026-06-02-feature-flags.md
```

The manager builds the three lanes in parallel worktrees, opens the MRs, then drives CI-fix / review / rebase per repo until the goal clears. Your only input after that is any escalation.

## Details

Manager orchestration loop, authorization model, guardrails, and the per-repo block: see [orchestration.md](orchestration.md).

## Delegates to

`/grill-with-docs`, `/mr`, `/ci`, `/review-pr`, `/worktree`; agent personas Frontend Staff Engineer, Backend Staff Engineer, and PR Reviewer (via Agent `subagent_type`).
