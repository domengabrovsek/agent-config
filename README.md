# Shared Agent Configuration

This is my setup for coding agents. The same config runs in Claude Code, Codex, and Pi.

## Why

Agents are good at writing code and bad at knowing when they're done. They start before they understand the problem, claim things they didn't check, and push work that fails CI. Most of that goes away with a few habits.

**Grill before building.** The agent questions me one decision at a time until we agree. It writes the plan down before it touches code.

**Give it a way to check its work.** It runs the repo's own checks before pushing, and backs every claim with a file, command, or test.

**Enforce with hooks, not prompts.** An agent can forget a rule. It can't skip a hook. Hooks block commits to main and PRs that fail their checks. A deny list blocks force-pushes, pushes to main, `rm -rf`, and reads of secrets.

**Fix mistakes once.** When an agent gets something wrong, the fix lands here as a rule or hook, so every future session has it.

**Bring in specialists.** Expert personas review security, database, cloud, and frontend work.

The cost is a few questions up front. Typos and one-liners skip the questions. The hooks still run.

## Quick start

You need `git`, `bash`, `jq`, `python3`, Node.js 22.19 or later, and at least one of Claude Code, Codex, or Pi.

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
- `--host claude`, `--host codex`, or `--host pi` sets up one host, plus the shared `~/.agents/` root.
- `--apply --adopt` replaces files that already exist, keeping a timestamped backup of each.
- If you commit changes to this repo, add a filter that keeps runtime state out of `settings.json` commits:

  ```bash
  git config filter.strip-ephemeral-state.clean 'jq "del(.feedbackSurveyState, .lastChangelogVersion, .autoMode)" 2>/dev/null || cat'
  git config filter.strip-ephemeral-state.smudge cat
  ```

For Pi, a machine that uses only some hosts, or how each host is wired, see [setup](docs/setup.md).

## What's inside

| Path | Holds |
| --- | --- |
| `AGENTS.md` | Shared instructions for every host |
| `rules/` | Detailed standards, loaded when a task needs them |
| `skills/` | Shared workflows, such as `/build`, `/mr`, and `/debug` |
| `agents/` | Expert personas, spawned as subagents |
| `settings.json` | Hook registry, deny list, and Claude Code settings |
| `hooks/` | Guardrail scripts that run on tool calls |
| `pi/` | Pi extensions, settings, models, and MCP servers |
| `scripts/` | Host setup, CI checks, and utilities |
| `templates/`, `references/` | Doc templates and review checklists that skills use |
| `tests/` | Tests for the hooks, host setup, and Pi extensions |
| `docs/` | The docs below |

[How it works](docs/architecture.md) shows how these pieces reach each host and when each one loads.

## Docs

| Doc | Covers |
| --- | --- |
| [How it works](docs/architecture.md) | The pieces, how hosts load them, and the enforcement layers |
| [Setup](docs/setup.md) | Install, host wiring, and machine scope |
| [Hooks](docs/hooks.md) | Every hook, what it blocks, and the deny list |
| [Rules](docs/rules.md) | Which rules load when, and enforcement tags |
| [Skills](docs/skills.md) | Every skill, how skills load, and how `/deliver` runs |
| [Personas](docs/personas.md) | The personas, lane mode, and panel mode |
| [Contributing](docs/contributing.md) | Changing the config and running the checks |
| [Decisions](docs/decisions.md) | Why it works this way |
| [Cheatsheet](CHEATSHEET.md) | Which skill fits a task |
| [Context](CONTEXT.md) | Glossary |
