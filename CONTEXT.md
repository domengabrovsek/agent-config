# Agent Config

The domain language for this repo's multi-host configuration, agent-orchestration model (how the main session delegates parallel work to spawned agents, and the two coordination shapes that delegation can take), and skill model (how skills are invoked and layered).

## Language

### Multi-host configuration

**Agent host**:
A coding-agent runtime that consumes this repo's shared instructions and skills, currently Claude Code, Codex, and Pi. Called a **harness** in repo naming and prose; the two words are synonyms.
_Avoid_: "agent" when referring to the runtime - reserve agent for a model-driven worker or session.

**Shared instruction source**:
The concise root `AGENTS.md`, which holds only always-needed host-neutral guidance loaded by every supported agent host.
_Avoid_: "Codex instructions", "Claude rules" when the guidance applies across hosts.

**Shared skill library**:
The repo's `skills/` tree, exposed to Claude Code through `~/.claude/skills` and to every host through the Shared root.
_Avoid_: "Claude skills", "Codex skills" when the skill follows the shared Agent Skills format.

**Shared root**:
The repo-owned `~/.agents/` directory, linked on every host, holding the trees a shared skill may name by absolute path: `skills`, `rules`, `scripts`, `templates`, `references`, `agents`, and the pull request template. A shared file names `~/.agents/...`, never a host's own config dir.
_Avoid_: `~/.claude/...` inside `skills/`, `rules/`, or `agents/` for anything but a genuinely Claude-only mechanism such as hooks.

**Compatibility notation**:
Legacy Claude-oriented names in shared skills that each agent host interprets through its equivalent capability, including `/name`, `$ARGUMENTS`, `Agent`, and `SendMessage`.
_Avoid_: host-specific skill copies created only to rename an equivalent invocation or tool.

**Rulebook**:
The shared router skill that loads applicable detailed standards from the existing `rules/` tree for hosts that do not discover those files directly.
_Avoid_: copied or host-specific rule trees.

**Host adapter**:
Host-specific configuration that connects an agent host to the shared instruction source and translates only behavior that has no portable representation.
_Avoid_: "copy", "fork" - adapters must not duplicate shared guidance.

**Host bootstrap**:
The multi-host installer that checks or creates the filesystem links connecting supported agent hosts to this repo.
_Avoid_: "Codex setup script", "Claude setup script" for the shared installer.

**Behavioral parity**:
Equivalent host-neutral guidance and skills across supported agent hosts, even when invocation syntax differs.
_Avoid_: "full parity" - hooks, permissions, and subagent mechanics are outside this boundary.

**Mechanical parity**:
Equivalent enforcement through host-specific hooks, permissions, notifications, and subagent configuration.
_Avoid_: "behavioral rules" - this parity is enforced by the host rather than model attention.

**Deny list**:
The machine-readable deny rules in the root `settings.json`, canonical enforcement input that each host's mechanical layer translates (allow rules are inert under deny-wins precedence).
_Avoid_: "Claude permissions" (hosts other than Claude consume it), "blocklist".

**Permission gate**:
pi's mechanical enforcement of the Deny list by intercepting model tool calls before execution.
_Avoid_: "sandbox", "security boundary" - an in-process gate is friction, not isolation.

**Derived policy**:
A permission config a host mechanism consumes, generated from the Deny list rather than hand-edited; staleness is Drift.
_Avoid_: "synced permissions", hand-edited copies of Deny-list rules.

**Drift**:
A host's links diverging from the checkout; the Host bootstrap detects it with `--check` and repairs it with `--apply`.
_Avoid_: "config drift", "stale links", "out-of-sync".

**Workflow state**:
Cross-session research, plans, specs, and diaries shared by every agent host under the historical `.claude/state/` project path.
_Avoid_: "Claude state" - the path is retained for compatibility, but ownership is multi-host.

### Agent orchestration

**Teammate**:
A named agent spawned via the Agent tool (the `name` parameter makes it addressable). Both coordination modes spawn named teammates.
_Avoid_: "subagent" when the agent is named - reserve subagent for the generic Agent-tool spawn mechanism.

**Lane mode**:
Parallel teammates in isolated git worktrees, each owning disjoint files, running in the background and reporting to the parent via completion notifications with no peer messaging.
_Avoid_: "fan-out mode", "worktree mode".

**Panel mode**:
Named read-only teammates that coordinate peer-to-peer via SendMessage to challenge each other, then settle on one combined answer for the parent.
_Avoid_: "round-table", "team mode".

**Peer session**:
Another pi session on this machine, addressable directly for coordination; exists outside the spawn relationship, unlike a Teammate.
_Avoid_: "subagent", "teammate" for cross-session peers.

**Advisory persona**:
A persona whose frontmatter `tools` list excludes Edit/Write/NotebookEdit, so mutating a file takes a deliberate shell command rather than one tool call (PR Reviewer, Cybersecurity Expert, GDPR Expert, Product Manager, UX Expert). These personas keep Bash, which they need for `git diff` and `gh`, so the brief still carries the read-only instruction.
_Avoid_: "read-only agent", "reviewer agent", "mechanically read-only" - Bash makes the guarantee partial.

**Writer persona**:
A full-tool persona that can mutate files and therefore serve as a lane-mode teammate.
_Avoid_: "builder agent", "implementer agent".

### Skill model

**Model-invoked skill**:
A skill the model may auto-invoke because its `description` carries trigger phrasing; the default for reusable disciplines.
_Avoid_: "auto skill".

**User-invoked skill**:
A skill only a human can start (`disable-model-invocation: true`, human-facing description); reserved for orchestration a human should sequence deliberately.
_Avoid_: "manual skill", "slash-only skill".

**Orchestrator**:
A skill that sequences other skills into a workflow.
_Avoid_: "pipeline", "flow".

**Reusable discipline**:
A single-purpose skill holding one repeatable practice, invoked by an orchestrator or the model.
_Avoid_: "helper skill".

**Seam**:
The agreed point where a test exercises behaviour; chosen highest and fewest, fixed during spec and reused by test and build.
_Avoid_: "mock point".

**Decision ticket**:
A wayfinder map entry that resolves to a decision, not a deliverable.
_Avoid_: "task", "story".

**Prototype detour**:
A throwaway spike taken to de-risk one decision, after which the code is discarded and only the learning kept.
_Avoid_: "spike task", "POC".

### Config surface

**Always-loaded rule**:
A rule in `CLAUDE.md` or an `@`-imported file under `rules/`, present in the context of every session regardless of the task.
_Avoid_: "global rule", "base rule".

**On-demand rule**:
A rule that enters context only when its trigger fires: `paths:` frontmatter matching a touched file, or a model-invoked skill matching the request. Costs nothing in sessions that never touch its trigger.
_Avoid_: "lazy rule", "scoped rule".

**Prose gate**:
The mechanical tier of the writing policy: the word lists, filler phrases and punctuation checks in `hooks/prose-gate.sh`, applied to markdown writes, commit messages and PR bodies. Distinct from the code-structure checks in `hooks/post-edit-lint.sh`, which fire on comment shape and language rules rather than word choice.
_Avoid_: "the lint hook", "the style check".

**Judgment tier**:
The half of the writing policy no regex can check: forced triads, synonym cycling, sentences naming a feeling instead of a mechanism. Lives in the `write-plain` skill, so it triggers on prose work rather than loading every session.
_Avoid_: "soft rules", "style guide".

## Relationships

- Each **Agent host** loads the **Shared instruction source** through its **Host adapter**.
- Each **Agent host** discovers the same **Shared skill library** through its native user-level path.
- Every **Agent host** also gets the **Shared root**, so one absolute path in a shared file resolves everywhere.
- Each **Agent host** maps **Compatibility notation** to its native skill and teammate mechanisms.
- The **Host bootstrap** installs every **Host adapter** while the legacy Claude setup command remains a compatibility entrypoint.
- The **Host bootstrap** leaves provider, model, and credential choices to each **Agent host** user.
- A **Host adapter** may add host-specific behavior but must not redefine shared guidance.
- **Behavioral parity** is the first multi-host milestone; **Mechanical parity** is translated and verified separately for each host.
- A **Permission gate** enforces the **Deny list** on one Agent host; rules without a translation for that host are surfaced, not silently dropped.
- All hosts translate one canonical **Deny list**; a host may enforce a superset, never a subset.
- A host's permission mechanism derives its rules from the **Deny list**; a generated or synced copy is acceptable, a second hand-maintained policy file is not.
- **Drift** between the checkout and a host is surfaced at that host's session start.
- **Behavioral parity** covers interactive and non-interactive modes supported by each **Agent host**.
- Every **Agent host** reads and writes the same **Workflow state** so work can move between hosts without conversion.
- Detailed standards live in **Reusable disciplines** and load on demand rather than expanding the **Shared instruction source**.
- The **Rulebook** exposes detailed `rules/` standards as one **Reusable discipline** without changing their source location.
- A **Teammate** runs in either **Lane mode** or **Panel mode**.
- A **Peer session** is another session on this machine reachable through the intercom broker; only Teammates are spawned, and only Peer sessions exist before and after one conversation.
- Our repo keeps **Orchestrators** at the **Model-invoked** layer (grill and build auto-fire as workflow phases); only `wayfinder` is a **User-invoked** orchestrator.
- A **Reusable discipline** is always **Model-invoked**; an **Orchestrator** may invoke disciplines.
- `wayfinder` resolves **Decision tickets** one per session until the fog clears, then hands to the spec stage.
- **Lane mode** is for mutating work (build/implementation); **Panel mode** is for read-only work (research, grilling, design).
- An **Advisory persona** can join **Panel mode** only; a **Lane mode** teammate must be a **Writer persona**.
- An **Always-loaded rule** competes for attention in every session; an **On-demand rule** does not. A rule with a mechanical trigger (file path or unambiguous phrase) belongs on demand.
- The **Prose gate** and the **Judgment tier** split one policy by what a regex can see. A pattern that fires on correct usage belongs in the **Judgment tier**, not the gate.
- The distinguishing axis is coordination topology: **Lane mode** is a star (teammates report only to the parent), **Panel mode** is a mesh (teammates also message each other). Worktree isolation follows from this: lanes mutate files so they need worktrees, panels are read-only so they do not.

## Example dialogue

> **Dev:** "I'm running /build on three file-isolated tracks - should the teammates talk to each other?"
> **Maintainer:** "No, that's lane mode - each owns its files, runs in a worktree, and reports back via notification. Peer messaging is panel mode, for /research and /grill where teammates need to challenge each other's findings before converging."

## Flagged ambiguities

- "harness" and "host" named the same runtime - resolved: synonyms; prose and the repo name say **harness**, while inherited script names, flags, and upstream-shared files keep "host" so merges stay conflict-free.
- "Agent" was used for both the coding runtime and a model-driven worker - resolved: the runtime is an **Agent host**; a named worker is a **Teammate**.
- Pi was described as a design target - resolved: Pi is a supported **Agent host** within the **Behavioral parity** boundary.
- "Full Pi support" was ambiguous - resolved: Pi loads shared behavior in every native mode; **Teammate** spawning (including background runs and panel-style steering) carries mechanical parity through the `pi-subagents` package.
- "subagent" was used for both the generic spawn mechanism and a named agent - resolved: a named agent is a **Teammate**; "subagent" refers only to the generic Agent-tool spawn.
- "skill" was used for both sequencing workflows and single practices - resolved: a sequencing skill is an **Orchestrator**, a single-practice skill is a **Reusable discipline**.
- "full permission parity for pi" was ambiguous - resolved: the pi **Permission gate** enforces a **superset** of the **Deny list** on file tools (Edit rules also bind writes; bash matching covers command segments), so any parity claim names its direction.
