# Cheatsheet

Intent → skill. Claude Code accepts the `/name` notation shown below. In Codex or Pi, invoke the same shared skill by name; host-specific notation in a skill maps to the equivalent available capability.

For full descriptions of each tool see the [README](README.md).

## "I want to..."

| Intent | Tool |
| --- | --- |
| Understand an unfamiliar code area | `/research <topic>` |
| Define formal requirements before planning | `/spec <topic>` |
| Stress-test a plan / reach alignment before code | `/grill-with-docs <topic>` |
| Build the agreed plan | `/build` |
| Write tests for code (TDD or prove-it) | `/test <target>` |
| Investigate a prod incident with evidence-first hypothesis ranking | `/debug <error>` |
| Resolve a GitHub issue end-to-end | `/fix-issue 1234` |
| Review someone's PR | `/review-pr 567` |
| Verify everything before pushing | `/verify-done` |
| Open a PR/MR (auto-runs verify-done first, regex-checks the title) | `/mr` |
| Watch CI on the latest PR | `/ci` (or `/loop 2m /ci`) |
| Cut a release | `/ship` |
| Make a diagram (mermaid or drawio) | `/diagram <topic>` |
| Save the session's work as a diary entry | `/summarize` |
| Refresh a library's API docs (React, Prisma, Next.js, etc.) | mention the library by name - the `ctx7` CLI auto-fires |
| Break a plan/PRD into independently-grabbable tracker issues | `/to-issues` |
| Find architectural deepening opportunities in a codebase | `/improve-codebase-architecture` |
| Scaffold a new skill | `/write-a-skill` |
| Create a worktree for parallel sub-agent work | `/worktree <slug>` |
| Clean up a worktree after its branch merged | `/worktree-merge` |
| Prune dead worktrees in this repo | `/worktrees [--apply]` |
| Audit worktrees across all repos under `~/dev/` | `/worktrees --all [--apply]` |
| Drive several PRs to done in parallel | `/drive-fleet` |
| Plan an effort too big for one session | `/wayfinder` |
| Hand this session to a fresh one | `/handoff` |
| Spike a throwaway prototype to settle a design question | `/prototype` |
| Review code for over-engineering only | `/prune` |

## When the slash IS the value

Some skills enforce a discipline plain English would skip. Use the slash when you want the structure:

- `/grill-with-docs` - the decision-tree walk is the point
- `/debug` - evidence-first hypothesis ranking before any code change
- `/build` - quality gates per task
- `/test` - red-green-refactor or prove-it pattern
- `/spec` - stakeholder-framed requirements doc
- `/verify-done` - every CI step in CI's exact order
- `/mr` - verify-done + commit-format + title-regex gates before opening
- `/ship` - pre-launch validation checklist
- `/fix-issue` - full issue resolution flow
- `/review-pr` - severity-tagged review scaffolding

## Skills that fire on their own

Model-invoked, so describing the work is enough. Naming them still works:

- `rulebook` - loads the detailed standards a task needs from `rules/`
- `write-plain` - fires on prose work: docs, ADRs, specs, PR bodies
- `jira` - fires on a Jira key, ticket mention, or an atlassian.net URL
- `sentry-issue` - fires on a Sentry short ID or a sentry.io URL

## When plain English is fine

Lightweight helpers; structure is minimal:

- `/diagram`, `/ci`, `/loop`, `/schedule`

## Workflow phases (4-phase)

```text
[/research]       optional orientation
        ↓
/grill-with-docs  alignment - emits CONTEXT.md terms + execution plan
        ↓
/build            walk the execution plan
        ↓
/verify-done      full quality gate
        ↓
/mr               open PR (gate runs again)
        ↓
/ci               watch pipeline
        ↓
/summarize        session diary
```

## Other intents

These run independently of the implementation workflow:

- `/debug` for incidents
- `/review-pr` for reviewing others' code
- `/document` for engineering docs
- `/diagram` for architecture or sequence diagrams
- `/resolve-conflicts` for an in-progress merge or rebase conflict
- `/wizard` for human-only setup steps (credentials, CI secrets, dashboards)
- `/wait-what` when the last reply did not land
- `/observability` for instrumenting a feature before the incident
- `/constraints` for a per-repo quality bar with ratchets

## Agents

Claude Code agents auto-spawn via `rules/agent-routing.md` when a task touches a specialized domain. Pi spawns the same personas as child sessions through the `pi-subagents` package, including background runs and worktree-isolated lanes. Codex maps `Agent` and `SendMessage` to its own teammate mechanisms when available, and follows the workflow locally otherwise. See [ADR 0008](docs/adr/0008-share-agent-config-across-hosts.md) for the shared boundary and [ADR 0009](docs/adr/0009-pi-adapter-vendored-settings-and-extensions.md) for the Pi adapter.
