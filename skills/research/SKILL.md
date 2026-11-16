---
name: research
description: "Starts Phase 1 (Research) for a topic: reads every relevant file, optionally runs a panel of Explore teammates, and saves a research artifact to .claude/state/research/. Use when the user says 'research <topic>' or '/research', or before planning work in unfamiliar code. Research only - proposes no solutions."
---

Start Phase 1 (Research) for the following topic: $ARGUMENTS

Resolve `$STATE` first: `.claude/state` in the main checkout of the repo being changed, per `rules/state-persistence.md`.

For bigger topics, run **panel mode** (see `rules/parallel-agents.md`): spawn one `Explore` teammate per subsystem, run one bounded cross-check round via SendMessage so teammates flag contradictions across their areas, then pull their findings together into the artifact yourself. For narrow topics, explore solo. Read all relevant files, check git history for context, and investigate related patterns.

Save the research artifact to `$STATE/research/YYYY-MM-DD-research-<topic>.md` (use today's date) containing:

- **Findings**: what you discovered in the codebase
- **Open questions**: things that need clarification
- **Constraints**: technical or business limitations
- **Related code**: key files and functions involved

Do NOT propose solutions yet. Research only.
