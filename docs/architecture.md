# How it works

One checkout holds the instructions, standards, workflows, personas, and guardrails for three coding agents. The agents are Claude Code, Codex, and Pi. `scripts/setup-hosts.sh` symlinks it into each agent's config dir, so an edit here reaches every host at once. Guidance lives in text the model reads. Hard limits live in hooks and a deny list that run outside the model.

## The problem it solves

Coding agents write code well and judge "done" badly, as the [README](../README.md#why) describes. Instructions help, but a long prompt competes for attention, and the agent forgets part of it as the session grows.

The repo answers with three design choices:

| Choice | How it works | Where |
| --- | --- | --- |
| Keep always-loaded text small | A word budget caps `AGENTS.md` plus the rules every session loads | `scripts/config-budget.sh` |
| Load detail only when a task needs it | Path-scoped rules, skills picked by their description, personas spawned per task | `rules/`, `skills/`, `agents/` |
| Enforce hard limits outside the model | Hooks run on tool calls, and a deny list blocks commands and paths | `settings.json`, `hooks/` |

[Decisions](decisions.md) records why each piece works the way it does.

## The pieces

| Path | Holds | How a session reaches it |
| --- | --- | --- |
| `AGENTS.md` | Shared instructions: priorities, writing, workflow, safety, git | Loaded at session start on every host |
| `rules/` | 15 detailed standards, such as git, tests, and comments | See [rules](rules.md) |
| `skills/` | 38 workflows, such as `/build`, `/mr`, and `/debug` | Picked by description, or typed as `/name`. See [skills](skills.md) |
| `agents/` | 18 expert personas | Spawned as subagents. See [personas](personas.md) |
| `settings.json` | Hook registry, deny list, and Claude Code settings | Read by each host. See [hooks](hooks.md) |
| `hooks/` | Guardrail scripts | Run on tool calls and session events |
| `mods/` | Claude Code plugins, such as the [pr-band](../mods/pr-band/README.md) status band | Linked at `~/.claude/mods`, loaded through `CLAUDE_CODE_PLUGIN_DIRS`. See [setup](setup.md#claude-code-environment) |
| `pi/` | Pi extensions, settings, models, and MCP servers | Linked into each Pi agent dir |
| `scripts/` | Host setup, CI checks, status line, notifications, worktree pruning | Run by you, CI, hooks, and skills |
| `templates/`, `references/` | Doc templates; security and testing checklists | Named by skills and personas through `~/.agents/` |
| `tests/` | Tests for the hooks, host setup, and Pi extensions | Run by CI. See [contributing](contributing.md) |
| `CONTEXT.md` | Glossary of the terms these docs use | Read by people and by `/grill-with-docs` |

### Scripts

Each script runs on its own. Hooks, skills, and CI call them, and you can run any of them by hand.

| Script | Does | Called by |
| --- | --- | --- |
| `setup-hosts.sh` | Links each host to the checkout; `--check` reports drift | You, `symlink-check.sh`, Pi `drift-check` |
| `setup-symlinks.sh` | Claude Code-only wrapper around `setup-hosts.sh` | You |
| `config-budget.sh` | Caps the words in the always-loaded text | CI |
| `config-integrity.sh` | Checks that JSON parses, no runtime keys are committed, and the git filter is declared | CI |
| `shellcheck-all.sh` | Lints every tracked shell script at warning level | CI |
| `pr-ready.sh` | Reports whether a PR is ready to merge; `--watch` polls until it settles | `post-pr-open-watch.sh`, `/mr`, `/deliver` |
| `notify.sh` | Shows a macOS notification unless a terminal or IDE is in front | `/ci`, `/deliver` |
| `worktree-prune.sh` | Removes worktrees whose branch merged or lost its upstream | `worktree-cleanup.sh`, Pi `worktree-cleanup`, `/worktrees`, `/worktree-merge`, `/summarize` |
| `statusline.sh` | Draws the Claude Code status line | `statusLine` in `settings.json` |

## How each host finds the config

![Host wiring](diagrams/host-wiring.png)
*Source: [`host-wiring.drawio`](diagrams/host-wiring.drawio)*

The diagram shows the checkout on the left and the four linked locations on the right. `scripts/setup-hosts.sh --apply` creates the links, and `--check` reports any that drifted.

- [Setup](setup.md#links-per-host) lists every link per host, and [scope a machine](setup.md#scope-a-machine) the variables that change the default dirs.
- [Hooks](hooks.md#host-coverage) shows how each host runs the hooks.
- [Decisions](decisions.md#hosts) records why every host links to one checkout.

## What a session loads

Most of the config costs nothing until a task needs it.

| When | What enters the session | Host |
| --- | --- | --- |
| Session start | `AGENTS.md` and the 9 rules without `paths:` frontmatter | Claude Code |
| Session start | `AGENTS.md` only | Codex, Pi |
| A touched file matches a rule's `paths:` glob | That rule, such as `rules/typescript.md` for a `.ts` file | Claude Code |
| A task needs a standard | The `rulebook` skill loads the matching `rules/` file | Codex, Pi |
| A request matches a skill's description | That skill's `SKILL.md` | All |
| A task touches a specialized domain | A persona, in a subagent with its own context | All |
| A tool call matches a registry entry | Hooks run; they add text only when they block or report | Claude Code, Codex |
| A `bash`, `edit`, or `write` call | Hooks run through the `hook-bridge` extension | Pi |

The main session never reads a persona file. [Decisions](decisions.md#spawn-personas-as-subagents) gives the reason.

## Enforcement layers

A rule the model must remember is weaker than a check the model cannot skip. Every rule bullet in `rules/`, persona guardrails, and skill rules ends with a tag naming what enforces it: `(hook)`, `(lint)`, `(CI)`, `(persona)`, or `(review-time: <why>)`. The tag tells a reader how much to trust a rule. A `(review-time)` tag must say why no hook can check it, so each one marks a candidate for a stronger check. [Rules](rules.md#enforcement-tags) explains each tag and its cost of a miss.

The deny list in `settings.json` sits beside the hooks. [Hooks](hooks.md#the-deny-list) lists its rule groups and what it cannot catch.

## Context budget

Every always-loaded word competes for attention in every session. `scripts/config-budget.sh` caps the words and `(review-time)` tags in `AGENTS.md` plus the always-loaded rules, and CI fails above the cap. A new rule that fits a file pattern gets `paths:` frontmatter, and a new procedure goes into a skill. Raising the cap is a deliberate edit to the script, reviewed in the same pull request as the rule that needs it. [Rules](rules.md#the-budget) gives the limits.

## Workflow state

Skills and hooks share state through files under `.claude/state/` in the project being worked on. Every host reads and writes the same paths, so work moves between sessions and hosts without conversion. This repo gitignores it, because here the files are personal notes.

| Path | Written by | Read by |
| --- | --- | --- |
| `research/` | `/research`, `/debug`, `/fix-issue` | Later sessions |
| `specs/` | `/spec` | `/plan`, Spec Verifier, `pre-pr-evidence-gate.sh` |
| `plans/` | `/plan`, `/grill-with-docs`, `/fix-issue`, `/drive-fleet` | `/build`, `/worktree` |
| `sessions/` | `/summarize` | People |
| `runs/<branch>/tasks.md` | `/deliver`, `/build` | The same skills, when resuming after compaction |
| `runs/<branch>/tests.lock` | QA Expert | `pre-edit-test-lock.sh` |
| `runs/<branch>/evidence.md`, the evidence ledger | Spec Verifier | `pre-pr-evidence-gate.sh`, before a PR opens |
| `runs/<branch>/reply-drafts.md` | `/pr-comments` | You, before posting a reply to a human |
| `wayfinder/<effort>.md` | `/wayfinder` | `/wayfinder` in later sessions |

`<branch>` is the branch name with `/` replaced by `-`. The test lock and evidence hooks look in the current worktree first, then in the main checkout.

## Where to go next

The [README docs table](../README.md#docs) lists every doc and what it covers.
