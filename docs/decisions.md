# Decisions

The design decisions this config still runs on. Each entry states the choice and the reason, and some name when to revisit it. The original ADRs, with their context and rejected alternatives, stay in git history under `docs/adr/`.

## Workflow

### Grill before building

- The Workflow section of `AGENTS.md` names five phases: Research, Grill, Spec and plan, Implement, Summarize. Each phase has a trigger, such as unfamiliar code for Research or checkable criteria for Spec and plan.
- The request's intent picks the phases, so a review or an explanation skips planning and implementation.
- The grill aligns through real-time questions instead of an annotated plan document. An annotated plan mixes domain terms, decisions, and task steps in one file, and each round is a slow write, read, and annotate cycle. The grill settles one decision per answer while the user is present.
- Each phase hands off explicitly. The grill ends when the user confirms a shared understanding, and approval of the spec gates implementation.
- The grill writes domain terms to `CONTEXT.md` and a short plan to `.claude/state/plans/`. It never writes an ADR. The glossary grows across sessions, while the plan is discarded once the work ships.
- Trivial changes, such as typos, version bumps, and config tweaks, skip the grill.
- Cost: the grill needs the user present to answer.

### No cross-session repo lock

- The config has no lock between sessions. Concurrent sessions run in different repos, so the same-checkout race a lock prevents does not occur.
- Worktrees serve parallel teammates and personal preference. Rules and skills ask for them, and no hook forces them.
- Revisit if two long-lived sessions start sharing one checkout.

## Agents

### Spawn personas as subagents

- A specialized task spawns the matching persona through the Agent tool. Persona files never load into the main conversation.
- Persona text in the main thread costs thousands of tokens and biases unrelated work later in the session.
- `rules/agent-routing.md` holds one routing row per routed persona. Doc Reader has none, because only `/document review` spawns it.

### Lean personas that inherit the rules

- Personas are short spawn-time briefs: role, working method, repo-specific guardrails, red flags, and output format. [`agents.md`](agents.md) has the skeleton.
- A persona never restates `rules/`. Custom subagents already receive the user `CLAUDE.md`, which links to `AGENTS.md`, and the always-loaded rules.
- Advisory personas drop Edit and Write through `tools:` frontmatter, so they cannot act as lane-mode writers.
- Revisit if custom subagents stop receiving user instructions, for example through `omitClaudeMd`.

### Lane mode and panel mode

- Mutating parallel work uses lane mode: teammates in isolated worktrees own disjoint files and report to the parent.
- Read-only research, grilling, and design use panel mode: named teammates challenge each other through SendMessage, then the parent converges.
- Implementation needs isolated writers, while research and grilling need teammates that challenge each other. A teammate that only reports to the parent never sees another teammate's findings.
- Research panels spawn as `Explore`, which has no Edit or Write tool. Grill and design panels use domain personas, often writers with every tool. A read-only brief keeps them from editing, because the Agent tool cannot restrict tools per spawn.
- The entry-point skills (`research`, `grill-with-docs`, `build`) pick the mode, so a prompt does not have to.
- `CONTEXT.md` defines both modes, and `rules/parallel-agents.md` holds the rules.

### Drive a fleet with one manager and /goal

- `drive-fleet` plans file-isolated lanes through a grill. One manager session then loops under the built-in `/goal`.
- Subagents in worktrees do every edit, review, and rebase. The manager never touches a working tree.
- A main session that edits every branch itself fills its context, lets one lane's edits overwrite another's, and blocks its turn polling CI.
- Setting the `/goal` authorizes opening the fleet's pull requests and in-scope fixes, retries, and rebases.
- The loop always stops for a plan-breaking conflict, the same CI failure three times, or an outward post-completion action.

### Deliver a feature with one human gate

- `deliver` runs research, spec, plan, the tests-first slice loop, spec verification, the PR, CI, and bot comments in one run.
- The user approves the spec, which is the one decision gate. After that the run stops only to post a reply to a human reviewer, or before a force-push, merge, push to `main`, production change, data deletion, or change outside the repo. `/plan` also asks about an architectural choice the spec left open. The user merges the PR.
- One gate is enough because the approved spec fixes the acceptance criteria. The Spec Verifier and the evidence gate check later stages against them.
- The author of code never grades its own tests. The QA Expert writes and locks the tests, a domain persona or the session writes the code, a read-only review panel reviews, and the Spec Verifier records evidence at HEAD.
- Three hooks back the loop, so a role cannot skip its limit. The evidence gate blocks a PR until every automated criterion passes at HEAD. The test lock blocks implementers from editing locked tests. The reply gate blocks inline replies to human comments.

## Skills

### Vendor and adapt upstream skills

- Upstream skills are adapted, not copied. Each names its upstream, usually in a `> Source:` line, and drifts from upstream on purpose. Here orchestration is model-invoked, while upstream makes the user type each stage, so verbatim copies would conflict.
- Orchestration skills stay model-invoked, so the model enters workflow phases on its own. `wayfinder` and `deliver` are the exceptions: a long run starts only when the user asks.
- Upstream's user-invoked `to-spec` and `implement` stages are not adopted, because they exist to let the user sequence stages by hand. `to-tickets` is adopted as the model-invoked `to-issues`.
- Reusable disciplines merge into an existing skill, such as `test`, `debug`, or `review-pr`, when one fits. Disciplines are model-invoked on both sides, so they merge without conflict.
- `wayfinder` tracks multi-session efforts in files under `.claude/state/`, because this setup runs no issue tracker.
- Re-vendoring is manual. No upstream commit is pinned, because each sync repeats the judgment of what to adapt.

## Hosts

### One instruction file and skill library for every host

- `AGENTS.md` holds the shared instructions and `skills/` the shared skills for Claude Code, Codex, and Pi. Guidance copied per host drifts apart.
- `scripts/setup-hosts.sh` links each host's native path to the same files.
- Claude Code has no user-level `AGENTS.md`, so `~/.claude/CLAUDE.md` links to it.
- Claude Code loads `rules/` natively through `~/.claude/rules`. Other hosts reach it through the `rulebook` skill.
- Tool hooks run on every host from one registry in `settings.json`. Claude Code runs it natively. Codex (through a generated `~/.codex/hooks.json`) and Pi (through the `hook-bridge` extension) call `hooks/lib/dispatch.sh`, so each check stays one script.
- Session hooks differ by host. Codex gets `SessionStart` and `SessionEnd` but no `Notification`. Pi runs its session work in its own extensions.
- The deny list stays in `settings.json`. Claude Code enforces it natively. Pi enforces a policy that the `permission-gate` extension derives from it for the pinned `pi-permission-system` package. `hooks/deny-gate.sh` adds it for Codex and blocks shell commands that name a denied path on every host.
- Teammate mechanics stay host-specific.
- Shared skills keep Claude notation, and `AGENTS.md` maps it for the other hosts.

### Pi adapter under pi/

- `setup-hosts.sh` links `AGENTS.md`, `agents/`, and the files under `pi/` into every Pi agent dir.
- As links, Pi's extensions and settings show up in `setup-hosts.sh --check`, and `--apply` sets up a new machine without manual steps.
- Pi files live under `pi/` because the repo root keeps the Claude Code layout.
- `PI_CONFIG_DIRS` selects the dirs. The default is `~/.pi/agent` plus `~/.pi-personal/agent`.
- `pi/settings.json` uses the `strip-ephemeral-state` git filter, like `settings.json`, so runtime keys stay out of git.
- The checkout path is load-bearing. Moving it breaks every linked host at once.
