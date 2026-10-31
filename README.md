# Shared Agent Configuration

One checkout configures three coding agents, Claude Code, Codex, and Pi, with the same instructions, workflows, personas, and guardrails. `scripts/setup-hosts.sh` symlinks it into each agent's config dir, so an edit here reaches every host.

## Why

Coding agents write code well and judge "done" badly. They start before they understand the problem, claim results they did not check, and push work that fails CI. This config counters each failure with one mechanism:

| Mechanism | What it does | Details |
| --- | --- | --- |
| Grill before building | The agent settles one decision at a time with you, then writes the plan before any code. Typos and one-liners skip this step | [Decisions](docs/decisions.md#grill-before-building) |
| Verify before claiming | The agent runs the repo's own checks before a push and cites a file, command, or test for each claim | [Skills](docs/skills.md#verify-and-ship) |
| Hooks over prompts | Hooks run outside the model, so the agent cannot skip them. They block commits to `main` and PRs that fail their checks. A deny list blocks force-pushes, pushes to `main`, `rm -rf`, and reads of secrets | [Hooks](docs/hooks.md), [Guardrails](docs/decisions.md#guardrails) |
| Fix mistakes once | Each agent mistake becomes a rule or a hook here, so every later session gets the fix | [Rules](docs/rules.md) |
| Specialist personas | Security, database, cloud, and frontend reviews run as subagents with their own context | [Personas](docs/personas.md) |

## Quick start

Requirements: `git`, `bash`, `jq`, `python3`, Node.js 22.19 or later, and at least one of Claude Code, Codex, or Pi.

```bash
git clone git@github.com:domengabrovsek/agent-config.git
cd agent-config
bash scripts/setup-hosts.sh --check   # preview the links; changes nothing
bash scripts/setup-hosts.sh --apply   # create them
```

| Option | Effect |
| --- | --- |
| `--host claude`, `--host codex`, `--host pi` | Sets up one host, plus the shared `~/.agents/` root |
| `--apply --adopt` | Replaces existing files and keeps a timestamped backup of each |

You can also open an agent in the checkout and ask it to run the setup. Tell it to run `--check` first and to ask before `--adopt`.

To commit to this repo, first add the filter that keeps runtime state out of `settings.json`:

```bash
git config filter.strip-ephemeral-state.clean 'jq "del(.feedbackSurveyState, .lastChangelogVersion, .autoMode)" 2>/dev/null || cat'
git config filter.strip-ephemeral-state.smudge cat
```

[Setup](docs/setup.md) covers Pi, machines that use only some hosts, and how each host is wired.

## Layout

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
| [How it works](docs/architecture.md) | The pieces, each script, how hosts load them, and the enforcement layers |
| [Setup](docs/setup.md) | Install, host wiring, and machine scope |
| [Hooks](docs/hooks.md) | Every hook, what it blocks, the deny list, and the shared helpers |
| [Rules](docs/rules.md) | Which rules load when, and enforcement tags |
| [Skills](docs/skills.md) | Every skill, how skills load, and how `/deliver` runs |
| [Personas](docs/personas.md) | The personas, lane mode, and panel mode |
| [Contributing](docs/contributing.md) | Changing the config and running the checks |
| [Decisions](docs/decisions.md) | Why it works this way, and what each choice costs |
| [Cheatsheet](CHEATSHEET.md) | Which skill fits a task |
| [Context](CONTEXT.md) | Glossary |
