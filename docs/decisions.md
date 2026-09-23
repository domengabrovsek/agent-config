# Decisions

The design decisions this config still runs on. Each entry states the choice, the reason, and when to revisit it. The original ADRs, with their context and rejected alternatives, stay in git history under `docs/adr/`.

## Workflow

### Grill before building

- Work runs Research, Grill, Implement, Summarize, as the Workflow section of `AGENTS.md` describes.
- The grill aligns through real-time questions instead of an annotated plan document.
- Each phase hands off explicitly. The user's "ready" at the end of the grill is the approval gate.
- The grill writes domain terms to `CONTEXT.md` and a short plan to `.claude/state/plans/`. It never writes an ADR.
- Trivial changes, such as typos, version bumps, and config tweaks, skip the grill.
- Cost: the grill needs the user present to answer.

### No cross-session repo lock

- The config has no lock between sessions. Concurrent sessions run in different repos, and the old lock never caught a real collision.
- Worktrees serve parallel teammates and personal preference. Nothing forces them.
- Revisit if two long-lived sessions start sharing one checkout.

## Agents

### Spawn personas as subagents

- A specialized task spawns the matching persona through the Agent tool. Persona files never load into the main conversation.
- Persona text in the main thread cost 3-15K tokens and biased unrelated work later in the session.
- `rules/agent-routing.md` holds one routing row per persona.

### Lean personas that inherit the rules

- Personas are short spawn-time briefs: role, working method, repo-specific guardrails, red flags, and output format. [`agents.md`](agents.md) has the skeleton.
- A persona never restates `rules/`. Custom subagents already receive the user `CLAUDE.md`, which links to `AGENTS.md`, and the always-loaded rules.
- Advisory personas drop Edit and Write through `tools:` frontmatter, so they cannot act as lane-mode writers.
- Revisit if custom subagents stop receiving user instructions, for example through `omitClaudeMd`.

### Lane mode and panel mode

- Mutating parallel work uses lane mode: teammates in isolated worktrees own disjoint files and report to the parent.
- Read-only research, grilling, and design use panel mode: named teammates challenge each other through SendMessage, then the parent converges.
- Research panels spawn as `Explore`, which has no Edit or Write tool. Grill and design panels use domain personas with a read-only brief.
- The entry-point skills (`research`, `grill-with-docs`, `build`) pick the mode, so a prompt does not have to.
- `CONTEXT.md` defines both modes, and `rules/parallel-agents.md` holds the rules.

### Drive a fleet with one manager and /goal

- `drive-fleet` plans file-isolated lanes through a grill. One manager session then loops under the built-in `/goal`.
- Subagents in worktrees do every edit, review, and rebase. The manager never touches a working tree.
- Setting the `/goal` authorizes opening the fleet's pull requests and in-scope fixes, retries, and rebases.
- The loop always stops for a plan-breaking conflict, the same CI failure three times, or an outward post-completion action.

## Skills

### Vendor and adapt upstream skills

- Upstream skills are adapted, not copied. Each keeps a `> Source:` line and drifts from upstream on purpose.
- Orchestration skills stay model-invoked, so the model enters workflow phases on its own.
- Upstream's user-invoked stages (`to-spec`, `to-tickets`, `implement`) are not adopted.
- Reusable disciplines merge into an existing skill, such as `test`, `debug`, or `review-pr`, when one fits.
- `wayfinder` tracks multi-session efforts in files under `.claude/state/`, because this setup runs no issue tracker.
- Re-vendoring is manual. No upstream commit is pinned.

## Hosts

### One instruction file and skill library for every host

- `AGENTS.md` holds the shared instructions and `skills/` the shared skills for Claude Code, Codex, and Pi.
- `scripts/setup-hosts.sh` links each host's native path to the same files.
- Claude Code has no user-level `AGENTS.md`, so `~/.claude/CLAUDE.md` links to it.
- Claude Code loads `rules/` natively through `~/.claude/rules`. Other hosts reach it through the `rulebook` skill.
- Hooks, permissions, and teammate mechanics stay host-specific.
- Shared skills keep Claude notation, and `AGENTS.md` maps it for the other hosts.

### Pi adapter under pi/

- `setup-hosts.sh` links `AGENTS.md`, `agents/`, and the files under `pi/` into every Pi agent dir.
- `PI_CONFIG_DIRS` selects the dirs. The default is `~/.pi/agent` plus `~/.pi-personal/agent`.
- `pi/settings.json` uses the `strip-ephemeral-state` git filter, like `settings.json`, so runtime keys stay out of git.
- The checkout path is load-bearing. Moving it breaks every linked host at once.
