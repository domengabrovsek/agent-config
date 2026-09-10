# Shared Agent Configuration

Shared behavioral configuration for Claude Code, Codex, and Pi. It provides structured workflows, safety boundaries, code standards, and reusable engineering skills from one repo.

The root `AGENTS.md` is the concise shared instruction source. `skills/`, `rules/`, and the historical `.claude/state/` path are shared across agent hosts. Hooks, permissions, notifications, and teammate mechanics remain host-specific.

Claude Code uses selective links under `~/.claude/` plus a second account dir (default `~/.claude-personal`) via `CLAUDE_CONFIG_DIRS`. Codex and Pi link their native instruction paths to `AGENTS.md`.

Every host also gets `~/.agents/`, the shared root. It holds `skills`, `rules`, `scripts`, `templates`, `references`, `agents`, and the pull request template. A shared skill names `~/.agents/...` so one path resolves on every host.

## Quick start

```bash
# Clone the repo - the setup script auto-detects its own location
git clone git@github.com:domengabrovsek/agent-config.git
cd agent-config

# Report drift without changing anything
bash scripts/setup-hosts.sh --check

# Create only missing links and safe Codex config defaults; refuse conflicts
bash scripts/setup-hosts.sh --apply

# After reviewing conflicts, move them to timestamped backups and link them
bash scripts/setup-hosts.sh --apply --adopt

# Strip ephemeral state Claude Code and Pi write to settings.json at runtime
git config filter.strip-ephemeral-state.clean 'jq "del(.feedbackSurveyState, .lastChangelogVersion, .autoMode)" 2>/dev/null || cat'
git config filter.strip-ephemeral-state.smudge cat
```

The filter is per-clone, so a checkout that skips those two commands will commit whatever the host wrote at runtime, including the `autoMode` environment inventory. `scripts/config-integrity.sh` fails the build when that reaches a commit, and prints the two commands to fix it.

`--check` is read-only and exits nonzero when drift exists. `--apply` never replaces a real path or wrong symlink. `--adopt` is the only replacement mode, and it moves every conflict to an adjacent `<path>.bak.<timestamp>` backup instead of deleting it. The existing `scripts/setup-symlinks.sh` command remains a Claude-only compatibility wrapper.

### Machine host scope

A machine that does not use every default dir records its own scope in `~/.agents/hosts.env`, sourced by the bootstrap when present. Entries use the `:=` form, so a real environment variable still wins:

```sh
: "${CLAUDE_CONFIG_DIRS:=$HOME/.claude}"
: "${PI_CONFIG_DIRS:=$HOME/.pi/agent}"
: "${HARNESS_SKIP_HOSTS:=codex}"
```

`HARNESS_SKIP_HOSTS` applies only under `--host all`; an explicit `--host codex` always runs. `AGENT_HOSTS_ENV` relocates the file.

Without this, an argument-free `--check` re-derives the two-dir defaults and reports permanent drift on dirs the machine never adopted. That matters because the `drift-check` extension calls the script with no arguments and no environment, so the scope has to be a recorded fact rather than a shell prefix someone remembers to type.

For Codex, the bootstrap adds the shared-instruction fallback and a built-in TUI status line only when each setting is absent. It preserves an existing custom status line.

### Pi

Install Pi separately from the host configuration:

```bash
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
bash scripts/setup-hosts.sh --apply --host pi
```

The Pi selector links instructions, `extensions/`, `settings.json`, `models.json`, and `mcp.json` into every configured pi agent dir. `PI_CONFIG_DIRS` defaults to `~/.pi/agent` plus `~/.pi-personal/agent`; `PI_CODING_AGENT_DIR` overrides it. It links shared skills under `~/.agents/skills`. These resources apply in interactive, print, JSON, and RPC modes. See [Pi's usage documentation](https://pi.dev/docs/latest/usage).

The bootstrap does not install or upgrade Pi. It does not manage providers, models, credentials, project trust, tools, or isolation. Pi has no built-in sandbox, so unattended work needs an external boundary. See [Pi's security guidance](https://pi.dev/docs/latest/security). Auto-compaction stays off by choice: a long session is handed off or stopped rather than silently summarized.

The `permission-gate` extension derives pi's permission policy from the deny list in the root `settings.json` (the **Derived policy**): `Read` rules become `path_read` surfaces, `Edit`/`Write` rules `path_write`, `Bash` rules command patterns, and MCP rules are enforced rather than skipped. Mechanical enforcement is the pinned [`@gotgenes/pi-permission-system`](https://pi.dev/packages/@gotgenes/pi-permission-system) package; this extension regenerates its `config.json` at every session start and announces a stale policy loudly. Only deny rules are generated - the universal fallback is `allow` - so semantics stay deny-wins and headless sessions never prompt. Rules without a translation fail in tests, not at runtime. It remains friction, not a sandbox: deliberately obfuscated commands still win, so unattended pi work still needs the external boundary above.

Two more pinned packages complete the stack: [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) loads Notion, Slack, and Playwright from `pi/mcp.json`, plus each project's `.mcp.json` (host-specific config discovery stays off), and [`pi-intercom`](https://pi.dev/packages/pi-intercom) lets sessions message each other directly and lets delegated children escalate to their supervisor.

Agent delegation is provided by the [`pi-subagents`](https://pi.dev/packages/pi-subagents) package: shared personas (`agents/` tree) spawn as focused child pi sessions, background runs return control while the child keeps working, and worktree-isolated lanes come back with a managed branch. Its worktrees default to the system temp dir (`pi-parallel-*` branches; retarget with `PI_SUBAGENTS_WORKTREE_DIR`) and `worktree-prune` still sweeps them after merges. Note the shared `agents/` tree is reachable through the links, and agents can author personas into it - review `git status` after unusual runs.

Run `/reload` after installing MCP configuration. Authenticate Notion with `/mcp-auth notion` and Slack with `/mcp-auth slack`; credentials stay outside this repository. Project `.mcp.json` overrides global servers with matching names, and `.pi/mcp.json` has highest precedence. Pi does not import Claude's MCP configuration.

The pi resources themselves live in `pi/` (`settings.json`, `mcp.json`, `extensions/`) and are tracked like the claude root files. See [ADR 0009](docs/adr/0009-pi-adapter-vendored-settings-and-extensions.md) for the adapter boundary.

## What's inside

- **`AGENTS.md`** - concise host-neutral instructions loaded by every supported host. See [ADR 0008](docs/adr/0008-share-agent-config-across-hosts.md).
- **`CLAUDE.md`** - thin Claude Code adapter that imports `AGENTS.md` and Claude's modular rules.
- **`rules/`** - detailed standards loaded directly by Claude Code and through the `rulebook` skill by other hosts.
- **`agents/`** - Claude Code expert teammate personas. Equivalent host mechanics are deferred; routing is in [`rules/agent-routing.md`](rules/agent-routing.md).
- **`skills/`** - shared workflows such as `grill-with-docs`, `build`, `debug`, `research`, and `verify-done`.
- **`hooks/`** - Claude Code automation wired into `settings.json`; host-specific parity is deferred.
- **`scripts/`** - the multi-host bootstrap, its Claude compatibility wrapper, and utilities used by hooks and skills.
- **`docs/adr/`** - Architecture Decision Records.
- **`references/`** - long-form checklists (security, testing) loaded by skills on demand.
- **`templates/`** - boilerplate for new ADRs and docs.

## More

- **Security boundaries** - deny list, Bash restrictions, and lock-file protection live in [`settings.json`](settings.json).
- **CI** - `.github/workflows/pull-request.yml` runs six jobs. They cover markdown linting, the rule budget, the prose gate, the pi extension tests, the shell test suites, and config integrity. A single `Gate` check aggregates them.
- **Local gate** - `scripts/config-budget.sh`, `scripts/config-integrity.sh`, and `scripts/shellcheck-all.sh` each run standalone and are what CI invokes.
