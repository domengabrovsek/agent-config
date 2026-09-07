# Parallel Work with Agent Worktrees

**When to apply:** a task splits into 2+ independent sub-tasks touching different files.

**Lane mode** and **Panel mode** are defined in `CONTEXT.md`. Lane mode mutates files and needs worktrees; panel mode is read-only and does not.

## Rules

- Each teammate owns a distinct set of files. Never assign two teammates the same file `(review-time: requires knowing the file plan)`
- Every lane-mode teammate gets `isolation: "worktree"` on its Agent call. Concurrent edits to one working directory corrupt it `(review-time: tool-call parameter choice, not hook-gated)`
- Target 4 teammates, ceiling 5. More slices than that go in rounds, not concurrently. Three well-scoped teammates beat six narrow ones `(review-time: parallelism target)`
- Brief each teammate self-contained: goal, exact file paths, constraints and patterns to match, and the command that verifies the work `(review-time: prompt-quality judgment)`
- Launch independent teammates in one message with multiple Agent calls `(review-time: message-shape choice)`
- Lane mode: wait for completion notifications, do not poll. Panel mode inverts this - coordinate actively via SendMessage during the cross-challenge round `(review-time: behavioral discipline, mode-dependent)`
- Never let a panel teammate mutate files. Work that needs writes is lane mode `(review-time: mode-selection judgment)`

## When not to parallelize

Skip it for a single focused change, tightly coupled steps, work that fits in a handful of tool calls, or verifying your own finished work. Claude 5 models delegate eagerly and self-verify; spawn overhead beats the win on small tasks `(review-time: task-shape judgment)`

## Panel protocol

Read-only parallel work (research, grilling, design) runs bounded, never as free-form chatter:

1. Each teammate explores its area alone.
2. Each sees the others' output and sends targeted challenges - one pass for research, iterate to agreement for grilling and design.
3. The parent pulls the results together and puts the disagreement to the user as the next question. Teammates never message the user.

Research panels spawn as `Explore`, whose toolset drops Edit and Write, leaving a write reachable only through Bash. Grill and design panels use the domain personas from `rules/agent-routing.md` with a read-only brief, backstopped by the parent's review `(review-time: agent-type selection)`

Merging finished lanes: see the `worktree-merge` skill.
