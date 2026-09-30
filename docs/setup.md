# Setup

How to install this config, scope it per machine, and wire each host. For the big picture, see [how it works](architecture.md#how-each-host-finds-the-config). For why it works this way, see [decisions](decisions.md#hosts).

## How hosts find the config

- Every host shares `AGENTS.md`, `skills/`, `rules/`, `.claude/state/`, the hook registry, and the deny list. Each host wires hooks, permissions, notifications, and teammates its own way.
- Hosts hold symlinks to this checkout, not copies. An edit is live at once, and moving the checkout breaks every host.
- Every host also gets `~/.agents/`, the shared root. A shared skill names `~/.agents/...`, so one path resolves on every host.

## Requirements

| Tool | Needed by |
| --- | --- |
| `git`, `bash` | Everything |
| `jq` | `setup-hosts.sh` for Codex, and the `settings.json` git filter |
| `python3` | `hooks/lib/dispatch.sh` on Codex and Pi, and `config-integrity.sh` |
| Node.js 22.18 or later | `hooks/deny-gate.sh`, which runs its TypeScript directly. Without `node`, the deny gate allows everything |
| Node.js 22.19 or later | `npm test`, from the `engines` floor in `package.json`. This version also satisfies the deny gate |
| Claude Code, Codex, or Pi | At least one host |

## Install

`scripts/setup-hosts.sh` links each host to this checkout.

| Mode | Does | Exit code |
| --- | --- | --- |
| `--check` | Reports drift and changes nothing | 0 when clean, 1 when drift exists |
| `--apply` | Creates missing links and manages the Codex files. It never replaces a real path or a wrong symlink | 0 when clean, 1 when issues remain |
| `--apply --adopt` | Moves each conflict to `<path>.bak.<timestamp>`, then links it | Same as `--apply` |

- `--host claude`, `--host codex`, `--host pi`, or `--host shared` limits the run. Any explicit `--host` also manages the shared `~/.agents/` links.
- `--apply` rewrites `~/.codex/config.toml` and regenerates a stale `~/.codex/hooks.json`, each after a backup. Neither needs `--adopt`.
- A usage error exits 2.
- `scripts/setup-symlinks.sh` is a compatibility wrapper. With no arguments it runs `--apply --adopt --host claude`, which also adopts the `~/.agents/` links. `--check` or `--dry-run` runs `--check --host claude`.

## Links per host

| Host | Path in the host dir | Source in the repo |
| --- | --- | --- |
| Claude Code | `CLAUDE.md` | `AGENTS.md` |
| Claude Code | `settings.json` | `settings.json` |
| Claude Code | `agents`, `hooks`, `rules`, `skills`, `scripts`, `docs`, `references`, `templates` | The same-named dirs |
| Claude Code | `statusline.sh` | `scripts/statusline.sh` |
| Claude Code | `pull_request_template.md` | `.github/pull_request_template.md` |
| Codex | `AGENTS.md` | `AGENTS.md` |
| Codex | `config.toml` | A managed file, not a link. See [Codex](#codex) |
| Codex | `hooks.json` | A file generated from the `settings.json` hook registry |
| Pi | `AGENTS.md` | `AGENTS.md` |
| Pi | `agents` | `agents/` |
| Pi | `extensions`, `settings.json`, `models.json`, `mcp.json` | The same-named files in `pi/` |
| Shared root | `skills`, `rules`, `scripts`, `templates`, `references`, `agents` | The same-named dirs |
| Shared root | `pull_request_template.md` | `.github/pull_request_template.md` |

Claude Code gets `CLAUDE.md` because it reads `AGENTS.md` only at project level.

## Keep runtime state out of commits

Claude Code and Pi write runtime keys into `settings.json`. The two `git config` lines in the [quick start](../README.md#quick-start) install a clean filter that strips them. `.gitattributes` applies the filter to `settings.json` and `pi/settings.json`.

The filter is per-clone. A clone without it commits whatever the host wrote, including the `autoMode` environment inventory. `scripts/config-integrity.sh` fails the build when that reaches a commit and prints the fix.

## Scope a machine

These variables change what the bootstrap links:

| Variable | Default | Sets |
| --- | --- | --- |
| `AGENT_CONFIG_REPO` | The checkout the script runs from | The repo the links point to |
| `CLAUDE_CONFIG_DIRS` | `~/.claude ~/.claude-personal` | The Claude Code dirs. When unset, `CLAUDE_CONFIG_DIR` names one dir |
| `PI_CONFIG_DIRS` | `~/.pi/agent ~/.pi-personal/agent` | The Pi agent dirs. When unset, `PI_CODING_AGENT_DIR` names one dir |
| `CODEX_HOME` | `~/.codex` | The Codex dir |
| `HARNESS_SKIP_HOSTS` | Empty | Hosts to skip under `--host all`: `claude`, `codex`, `pi`, or `shared` |
| `AGENT_HOSTS_ENV` | `~/.agents/hosts.env` | The scope file |

The dir lists split on spaces, so a path containing a space is not supported.

A machine that skips some default dirs records its scope in the scope file. The bootstrap sources it when present. Entries use the `:=` form, so a real environment variable still wins:

```sh
: "${CLAUDE_CONFIG_DIRS:=$HOME/.claude}"
: "${PI_CONFIG_DIRS:=$HOME/.pi/agent}"
: "${HARNESS_SKIP_HOSTS:=codex}"
```

`HARNESS_SKIP_HOSTS` applies only under `--host all`. An explicit `--host codex` always runs.

The Pi `drift-check` extension runs `--check` for every host at each session start. Without the scope file, it reports drift on dirs this machine never adopted.

Two paths assume the default dirs:

- The hook commands and the status line in `settings.json` fall back to `~/.claude/...`. A machine that uses only `~/.claude-personal` still needs the `~/.claude` links.
- `pi/settings.json` loads the hook bridge into subagents from `~/.pi/agent/extensions/`. A machine with only `~/.pi-personal/agent` runs subagents without it.

## Codex

The bootstrap adds these `config.toml` settings, each only when absent:

| Setting | Value |
| --- | --- |
| `project_doc_fallback_filenames` | `["CLAUDE.md"]` |
| `model_context_window` | `1050000` |
| `model_auto_compact_token_limit` | `950000` |
| `[tui] status_line` | A built-in status line. A custom one stays |
| `[features] hooks` | `true` |

It refuses the whole config step in these cases, and `--adopt` does not help:

- `config.toml` is not a regular file.
- A setting or table appears twice, or a setting sits outside its table.
- The fallback list differs, or `hooks` is not `true`.

Fix the file by hand, then run `--apply` again.

It also writes `~/.codex/hooks.json`. The file sends `PreToolUse`, `PostToolUse`, `SessionStart`, and `SessionEnd` events to `hooks/lib/dispatch.sh`. Codex gets no `Notification` hook. An existing hooks file of your own needs `--adopt`. Review and trust the hooks file in Codex after each regeneration.

`hooks/deny-gate.sh` brings the deny list to Codex. It blocks Bash commands matching a `Bash` rule, edits and shell commands naming a denied path, and denied MCP tools. It adds friction, not a sandbox.

Codex runs `symlink-check.sh` at session start, but the dispatcher drops its warning. Run `bash scripts/setup-hosts.sh --check --host codex` by hand to see Codex drift.

## Pi

Install Pi separately, then link it:

```bash
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
bash scripts/setup-hosts.sh --apply --host pi
```

The Pi resources live in `pi/`. Shared skills come from `~/.agents/skills`, and `package.json` also declares this repo as a Pi package. The linked resources apply in interactive, print, JSON, and RPC modes, except the status line and herdr extensions, which run only in the TUI. See [Pi's usage documentation](https://pi.dev/docs/latest/usage).

The bootstrap does not install or upgrade Pi. It does not manage credentials, project trust, tools, or isolation. The linked `pi/settings.json` and `pi/models.json` do set the default provider, default model, and package list. Pi has no built-in sandbox, so unattended work needs an external boundary. See [Pi's security guidance](https://pi.dev/docs/latest/security). Auto-compaction stays off: a long session gets handed off or stopped, not silently summarized.

### Extensions

| Extension | Does |
| --- | --- |
| `permission-gate` | Derives Pi's permission policy from the deny list at each session start |
| `hook-bridge` | Runs the registry hooks on Pi's `bash`, `edit`, and `write` calls through `hooks/lib/dispatch.sh` |
| `drift-check` | Runs `setup-hosts.sh --check` at session start and warns on drift |
| `worktree-cleanup` | Runs `scripts/worktree-prune.sh --apply` at session shutdown |
| `statusline` | Replaces the footer with folder, branch, tokens, cost, context, usage windows, and model |
| `herdr-agent-state` | Reports session state to herdr when `HERDR_ENV=1` |

**`permission-gate`** turns `Read` rules into `path_read` surfaces, `Edit` and `Write` rules into `path_write`, and passes `Bash` and MCP rules through. The pinned [`@gotgenes/pi-permission-system`](https://pi.dev/packages/@gotgenes/pi-permission-system) package enforces the result. The extension writes `pi/extensions/pi-permission-system/config.json` and announces a stale policy.

- The generated policy holds only deny rules, and the fallback is `allow`, so deny wins and headless sessions never prompt.
- The bash surface lists its `*: allow` catch-all first, because the package applies the last matching rule.
- A rule without a translation fails in tests, not at runtime. Obfuscated commands still get through.

**`hook-bridge`** blocks a call when a hook exits 2, and appends hook feedback to the tool result. It fails open when the dispatcher is missing or times out. `pi/settings.json` loads it into subagent children through `subagents.defaultSubagentOnlyExtensions`. It reads the child's persona from the `<active_agent>` tag in its system prompt, so the test lock knows the QA Expert.

### Packages

- [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) loads Notion, Slack, and Playwright from `pi/mcp.json`, plus each project's `.mcp.json`. Host-specific config discovery stays off.
- [`pi-intercom`](https://pi.dev/packages/pi-intercom) lets sessions message each other and lets delegated children escalate to their supervisor.
- [`pi-subagents`](https://pi.dev/packages/pi-subagents) spawns the shared personas in `agents/` as child Pi sessions. Background runs return control while the child works, and worktree lanes come back with a managed branch. Its worktrees go to the system temp dir on `pi-parallel-*` branches, and `PI_SUBAGENTS_WORKTREE_DIR` retargets them. `worktree-prune` sweeps them after merges.
- `pi-ollama-cloud` adds the Ollama Cloud provider.

Agents can write personas into the linked `agents/` tree, so check `git status` after unusual runs.

### MCP servers

Run `/reload` after installing MCP configuration. Authenticate Notion with `/mcp-auth notion` and Slack with `/mcp-auth slack`. Credentials stay outside this repository. A project `.mcp.json` overrides global servers with matching names, and `.pi/mcp.json` has the highest precedence. Pi does not import Claude's MCP configuration.

## Check changes

[Contributing](contributing.md#run-the-checks) lists every CI job and the local command for each.
