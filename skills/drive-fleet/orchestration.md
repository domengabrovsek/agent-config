# Drive Fleet - Orchestration

The manager loop for Phase 2. The main loop is a MANAGER: it polls CI, dispatches subagents, tracks tasks, retargets/closes MRs, and triggers CI jobs. It NEVER mutates a working tree - no edits, reviews, rebases, or conflict resolution. All of that is delegated to background subagents, each in its own git worktree.

## Authorization model

Setting the `/goal` is a one-time human decision. It pre-authorizes the in-scope downstream work, with no per-MR checkpoint:

- **Hands-off.** Open MRs via `/mr`, auto-fix red, retry infra-flake jobs, rebase, and apply review fixes within the plan's lanes - no per-action approval.
- **Always hard-stop and escalate (never plow ahead) on:**
  - a plan-invalidating conflict (e.g. `main` diverged and broke file-isolation)
  - a structural CI failure (the same issue fails 3x - per `/ci`)
  - the outward `post_completion_action`

## The loop

1. **Build lanes in parallel.** One subagent per lane, each in its own git worktree, file-isolated, <=4-5 concurrent. Route by domain: Frontend Staff Engineer / Backend Staff Engineer (Agent `subagent_type`, `isolation: "worktree"`). Sequential sub-tickets that share files stay inside ONE agent.
2. **Open MRs.** Once lanes are pushed, open MRs via `/mr` - conventional commits, no co-author trailers, stacked-MR dependencies and retargeting.
3. **Poll CI in the background.** One Monitor per branch via `/ci` (emits only on status change, zero cost while running). React on Monitor notifications and agent-completion events - never block the manager turn polling.
4. **Per red MR - fix subagent.** Spawn a domain-expert subagent in that lane's worktree to diagnose and fix. Infra-flake or clearly-unrelated failure -> retry the job (`glab ci retry` / `gh run rerun`); real failure -> fix and push. Same issue 3x -> escalate to the user.
5. **Per green MR - review subagent.** Spawn a PR Reviewer subagent that applies `/review-pr` and fixes blockers + majors + one-line fixes in the worktree. Reviewer comments on the MR go through `/pr-comments`.
6. **Rebase + retarget.** Per branch, a subagent rebases onto latest `{target_branch}` (`--force-with-lease`, resolving conflicts). Retarget stacked MRs to `{target_branch}` as their bases merge.
7. **Close out.** When the WHOLE fleet meets the condition simultaneously, run the `post_completion_action` (if any) on each MR. Only then does the `/goal` clear.

## Guardrails - never violate

- **Manager-only.** The main loop never edits, reviews, rebases, or resolves conflicts. It polls CI, dispatches agents, tracks tasks, retargets/closes MRs, and triggers CI jobs - nothing that mutates a working tree.
- **One worktree per lane per repo.** Never two concurrent agents in the same worktree. Sequential file-sharing sub-tickets stay in one agent.
- **CI polling is backgrounded.** Pollers run as Monitors (per `/ci`), not in the manager turn. React on agent-completion and pipeline-terminal events.
- **Surface genuine conflicts.** If `main` diverges mid-session and invalidates the plan, stop and re-plan the affected MRs with the user. Do not plow ahead.
- **Hold the post-action.** Trigger `post_completion_action` only when the full condition holds across the whole fleet.
- **Cross-repo worktrees are manual.** When lanes span sibling repos under a non-git parent (e.g. `~/code/<project>/` holding several repos), there is no repo at the parent - manage each repo's worktrees individually (see `/worktree`).

## Per-repo block (fill in before running)

| Field | Example |
| --- | --- |
| `target_branch` | the repo's default branch, e.g. `main` |
| verification cmd | `npm run lint:fix && npm run typecheck && npm test && npm run build` |
| CI tool | glab / gh (auto-detected by `/ci`) |
| `post_completion_action` | trigger the `notify_reviewers` job / none |
| worktree root | per repo; the parent dir is NOT a git repo for multi-repo work |
