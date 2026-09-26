# Setup

How to install this config, scope it per machine, and check changes. For why it works this way, see [decisions](decisions.md#hosts).

## How hosts find the config

- `AGENTS.md`, `skills/`, `rules/`, and `.claude/state/` are shared by every host. Hooks, permissions, notifications, and teammate mechanics stay host-specific.
- Claude Code gets selective links under `~/.claude/`, plus a second account dir (default `~/.claude-personal`). `CLAUDE_CONFIG_DIRS` sets the list.
- Codex and Pi link their native instruction paths to `AGENTS.md`.
- Every host also gets `~/.agents/`, the shared root. It holds `skills`, `rules`, `scripts`, `templates`, `references`, `agents`, and the pull request template. A shared skill names `~/.agents/...`, so one path resolves on every host.

## Install

`scripts/setup-hosts.sh` links each host to this checkout. Pass `--host HOST` to limit it to one host.

- `--check` reports drift without changing anything. It exits nonzero when drift exists.
- `--apply` creates missing links and safe Codex config defaults. It never replaces a real path or a wrong symlink.
- `--apply --adopt` moves each conflict to an adjacent `<path>.bak.<timestamp>` backup, then links it. It is the only replacement mode.

`scripts/setup-symlinks.sh` remains a Claude-only compatibility wrapper.

## Keep runtime state out of commits

Claude Code and Pi write runtime keys into `settings.json`. The two `git config` lines in the [quick start](../README.md#quick-start) install a clean filter that strips them. The filter is per-clone. A clone without it commits whatever the host wrote, including the `autoMode` environment inventory. `scripts/config-integrity.sh` fails the build when that reaches a commit and prints the fix.

## Scope a machine

A machine that skips some default dirs records its scope in `~/.agents/hosts.env`. The bootstrap sources it when present. Entries use the `:=` form, so a real environment variable still wins:

```sh
: "${CLAUDE_CONFIG_DIRS:=$HOME/.claude}"
: "${PI_CONFIG_DIRS:=$HOME/.pi/agent}"
: "${HARNESS_SKIP_HOSTS:=codex}"
```

- `HARNESS_SKIP_HOSTS` applies only under `--host all`. An explicit `--host codex` always runs.
- `AGENT_HOSTS_ENV` relocates the file.

Without this file, an argument-free `--check` uses the two-dir defaults and reports drift on dirs the machine never adopted. The `drift-check` extension runs the script with no arguments and no environment, so the scope has to live in a file.

## Codex

The bootstrap adds these Codex settings, each only when absent:

- the shared-instruction fallback
- the long-context window and its compaction limit
- a built-in TUI status line, keeping any custom one

It also enables Codex hooks and writes `~/.codex/hooks.json`, which sends every hook event to `hooks/lib/dispatch.sh`. `hooks/deny-gate.sh` brings the deny list to Codex. It blocks Bash commands matching a Bash rule, edits and shell commands naming a denied path, and denied MCP tools. It adds friction, not a sandbox.

An existing hooks file of your own needs `--adopt`. Codex asks you to trust the hooks once, and again after each regeneration.

## Pi

Install Pi separately, then link it:

```bash
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
bash scripts/setup-hosts.sh --apply --host pi
```

The Pi resources live in `pi/`. The Pi selector links instructions, `agents/`, `extensions/`, `settings.json`, `models.json`, and `mcp.json` into every configured Pi agent dir. `PI_CODING_AGENT_DIR` overrides the `PI_CONFIG_DIRS` default. Shared skills come from `~/.agents/skills`. These resources apply in interactive, print, JSON, and RPC modes. See [Pi's usage documentation](https://pi.dev/docs/latest/usage).

The bootstrap does not install or upgrade Pi. It does not manage providers, models, credentials, project trust, tools, or isolation. Pi has no built-in sandbox, so unattended work needs an external boundary. See [Pi's security guidance](https://pi.dev/docs/latest/security). Auto-compaction stays off: a long session gets handed off or stopped, not silently summarized.

### Extensions

- **`permission-gate`** derives Pi's permission policy from the deny list in the root `settings.json`. `Read` rules become `path_read` surfaces, `Edit` and `Write` rules become `path_write`, `Bash` rules become command patterns, and MCP rules are enforced. The pinned [`@gotgenes/pi-permission-system`](https://pi.dev/packages/@gotgenes/pi-permission-system) package enforces the result. The extension regenerates its `config.json` at every session start and announces a stale policy.
- The generated policy holds only deny rules, and the fallback is `allow`, so deny wins and headless sessions never prompt. The bash surface lists its `*: allow` catch-all first, because the package applies the last matching rule. A rule without a translation fails in tests, not at runtime. Obfuscated commands still get through.
- **`hook-bridge`** runs the same hooks as Claude Code. It sends bash, edit, and write calls through `hooks/lib/dispatch.sh`, blocks a call when a hook exits 2, and appends hook feedback to the tool result. `pi/settings.json` loads it into foreground subagent children through `subagents.defaultSubagentOnlyExtensions`. It reads the child's persona from the `<active_agent>` tag in its system prompt.
- **`pi-ollama-cloud`** adds the Ollama Cloud provider.

### Packages

- [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) loads Notion, Slack, and Playwright from `pi/mcp.json`, plus each project's `.mcp.json`. Host-specific config discovery stays off.
- [`pi-intercom`](https://pi.dev/packages/pi-intercom) lets sessions message each other and lets delegated children escalate to their supervisor.
- [`pi-subagents`](https://pi.dev/packages/pi-subagents) spawns the shared personas in `agents/` as child Pi sessions. Background runs return control while the child works, and worktree lanes come back with a managed branch. Its worktrees go to the system temp dir on `pi-parallel-*` branches, and `PI_SUBAGENTS_WORKTREE_DIR` retargets them. `worktree-prune` sweeps them after merges.

Agents can write personas into the linked `agents/` tree, so check `git status` after unusual runs.

### MCP servers

Run `/reload` after installing MCP configuration. Authenticate Notion with `/mcp-auth notion` and Slack with `/mcp-auth slack`. Credentials stay outside this repository. A project `.mcp.json` overrides global servers with matching names, and `.pi/mcp.json` has the highest precedence. Pi does not import Claude's MCP configuration.

## Check changes

- **Local gate:** `scripts/config-budget.sh`, `scripts/config-integrity.sh`, and `scripts/shellcheck-all.sh` each run standalone. CI runs the same scripts.
- **CI:** `.github/workflows/pull-request.yml` runs the checks, and a single `Gate` check aggregates them.
- **Reviewer:** `.github/workflows/reviewer.yml` has Claude review each new or ready PR with inline comments. When the owner replies in a thread, Claude answers or resolves it. It needs the `CLAUDE_CODE_OAUTH_TOKEN` secret from `claude setup-token`.
