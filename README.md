# Shared Agent Configuration

This is my setup for coding agents. The same config runs in Claude Code, Codex, and Pi.

## Why

Agents are good at writing code and bad at knowing when they're done. They start before they understand the problem, claim things they didn't check, and push work that fails CI. Most of that goes away with a few habits.

**Grill before building.** The agent questions me one decision at a time until we agree. It writes the plan down before it touches code.

**Give it a way to check its work.** It runs the repo's own checks before pushing, and backs every claim with a file, command, or test.

**Enforce with hooks, not prompts.** An agent can forget a rule. It can't skip a hook. Hooks and a deny list block force-pushes, pushes to main, and `rm -rf`.

**Fix mistakes once.** When an agent gets something wrong, the fix lands here as a rule or hook, so every future session has it.

**Bring in specialists.** Expert personas review security, database, cloud, and frontend work.

The cost is a few questions up front. Typos and one-liners skip the questions. The hooks still run.

## Quick start

You need `git`, `bash`, `jq`, and at least one of Claude Code, Codex, or Pi.

The easiest path is to clone the repo, open your agent in it, and ask:

> Set this repo up for me with `scripts/setup-hosts.sh`. Run `--check` first, and ask me before using `--adopt`.

To do it by hand, clone the repo and link your hosts. These two steps are required:

```bash
git clone git@github.com:domengabrovsek/agent-config.git
cd agent-config
bash scripts/setup-hosts.sh --apply
```

The rest is optional:

- `bash scripts/setup-hosts.sh --check` previews what `--apply` changes, without touching anything.
- `--host claude`, `--host codex`, or `--host pi` sets up one host instead of all.
- `--apply --adopt` replaces files that already exist, keeping a timestamped backup of each.
- If you commit changes to this repo, add a filter that keeps runtime state out of `settings.json` commits:

  ```bash
  git config filter.strip-ephemeral-state.clean 'jq "del(.feedbackSurveyState, .lastChangelogVersion, .autoMode)" 2>/dev/null || cat'
  git config filter.strip-ephemeral-state.smudge cat
  ```

For Pi, a machine that uses only some hosts, or how each host is wired, see [setup](docs/setup.md).

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
