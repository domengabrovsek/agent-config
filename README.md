# Shared Agent Configuration

This is my setup for coding agents. The same config runs in Claude Code, Codex, and Pi.

## Why

Agents are good at writing code and bad at knowing when they're done. They start before they understand the problem, claim things they didn't check, and push work that fails CI. Most of that goes away with a few habits.

**Grill before building.** The agent questions me one decision at a time until we agree. It writes the plan down before it touches code.

**Give it a way to check its work.** It runs the repo's own checks before pushing, and backs every claim with a file, command, or test.

**Enforce with hooks, not prompts.** An agent can forget a rule. It can't skip a hook. Hooks and a deny list block force-pushes, pushes to main, and `rm -rf`.

**Fix mistakes once.** When an agent gets something wrong, the fix lands here as a rule or hook, so every future session has it.

**Bring in specialists.** Expert personas review security, database, cloud, and frontend work.

The cost is a few questions up front. Typos and one-liners skip all of it.

## How it works

```mermaid
flowchart LR
  research[Research] --> grill[Grill with you]
  grill --> spec[Spec: you approve]
  spec --> build[Build]
  build --> verify[Verify]
  verify -- fails --> build
  verify --> pr[Pull request]
  pr --> review[CI and review]
  review -- comments --> build
  review --> merge([You merge])
```

Each step is its own skill, listed in the [cheatsheet](CHEATSHEET.md). `/deliver <goal>` runs the loop in one pass once you approve the spec, and still leaves the merge to you.

## Quick start

```bash
git clone git@github.com:domengabrovsek/agent-config.git
cd agent-config

# Report drift, then link every host to this checkout
bash scripts/setup-hosts.sh --check
bash scripts/setup-hosts.sh --apply

# Keep the runtime state hosts write to settings.json out of commits
git config filter.strip-ephemeral-state.clean 'jq "del(.feedbackSurveyState, .lastChangelogVersion, .autoMode)" 2>/dev/null || cat'
git config filter.strip-ephemeral-state.smudge cat
```

For conflicts, Pi, or a machine that uses only some hosts, see [setup](docs/setup.md).

## What's inside

- `AGENTS.md` - shared instructions for every host
- `rules/` - detailed standards
- `skills/` - shared workflows
- `agents/` - expert personas
- `hooks/` - guardrail scripts
- `settings.json` - hook registry and deny list
- `scripts/` - bootstrap and utilities

## Docs

- [Setup](docs/setup.md) - install, hosts, and checks
- [Decisions](docs/decisions.md) - why it works this way
- [Agents](docs/agents.md) - persona catalog
- [Cheatsheet](CHEATSHEET.md) - intent to skill
- [Context](CONTEXT.md) - glossary
