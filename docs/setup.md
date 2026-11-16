# Setup

How to install this config, scope it per machine, and wire each host. For the big picture, see [how it works](architecture.md#how-each-host-finds-the-config). For why it works this way, see [decisions](decisions.md#hosts).

## How hosts find the config

- Every host shares `AGENTS.md`, `skills/`, `rules/`, `.claude/state/`, the hook registry, and the deny list. Each host wires hooks, permissions, notifications, and teammates its own way.
- Hosts hold symlinks to this checkout, not copies. An edit is live at once, and moving the checkout breaks every host. Run `bash scripts/setup-hosts.sh --apply --adopt` from the new location to relink them, including the Codex `hooks.json`.
- Each session start checks the links. Claude Code runs `hooks/symlink-check.sh`, which prints the fix command. Pi runs the [`drift-check`](#extensions) extension. Codex shows no warning, as [Codex](#codex) explains.
- Every host also gets `~/.agents/`, the shared root. A shared skill names `~/.agents/...`, so one path resolves on every host.

## Requirements

| Tool | Needed by |
| --- | --- |
| `git`, `bash` | Everything |
| `jq` | `setup-hosts.sh` for Codex, and the `settings.json` git filter |
| `python3` | `hooks/lib/dispatch.sh` on Codex and Pi, and `config-integrity.sh` |
| Node.js 22.18 or later | `hooks/deny-gate.sh`, which runs its TypeScript directly. Without `node`, the deny gate blocks every call on Codex and passes elsewhere |
| Node.js 22.19 or later | `npm test`, from the `engines` floor in `package.json`. Install this version, because it also satisfies the deny gate |
| Claude Code, Codex, or Pi | At least one host |

## Install

`scripts/setup-hosts.sh` links each host to this checkout. With no `--host`, it sets up every host, so `bash scripts/setup-hosts.sh --apply` is a full install.

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
| Claude Code | `agents`, `hooks`, `rules`, `skills`, `scripts`, `docs`, `references`, `templates`, `mods` | The same-named dirs |
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

## Claude Code environment

The `env` block in `settings.json` sets three variables for every Claude Code session:

| Variable | Value | Enables |
| --- | --- | --- |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | `1` | Claude Code's experimental agent teams feature, for the teammates that lane and panel mode spawn |
| `CLAUDE_CODE_PLUGIN_DIRS` | `~/.claude/mods/pr-band:~/.claude/mods/pr-fleet:~/.claude/mods/alerts` | Loads the [pr-band](../mods/pr-band/README.md), [pr-fleet](../mods/pr-fleet/README.md), and [alerts](../mods/alerts/README.md) mods from the linked `mods/` dir |
| `NODE_USE_ENV_PROXY` | `1` | Node's built-in `fetch` through the sandbox proxy. See [the sandbox](#claude-code-sandbox) |

`attribution` is empty for commits and PRs, so Claude Code does not ask for the trailers and footers the commit and PR gates refuse.

## Claude Code sandbox

`settings.json` turns on Claude Code's [sandbox](https://code.claude.com/docs/en/sandboxing) for every session on the machine. Bash commands run under OS-level limits:

| Limit | Setting |
| --- | --- |
| Reads | Every `Read(...)` deny rule also blocks subprocesses, so no command reads `~/.config/gcloud`, `~/.aws`, or `~/.ssh`. `allowRead` reopens `~/.config/gh/hosts.yml`, so `gh` works |
| Writes | The working directory, every repo under `~/dev`, plus `~/.npm`, `~/.terraform.d/plugin-cache`, the agent gcloud dir, the agent cache `~/.cache/agent`, and the build lock, activity, and refs under `~/.docker/buildx`. The rest of `~/.docker/buildx` stays read-only, because it chooses and configures the builder. On macOS only, each repo's `.husky` dir under `~/dev` and its `.claude` settings files, `hooks`, `skills`, `agents`, and `commands` stay read-only, so a command cannot plant a hook that runs outside the sandbox. A new worktree's install therefore cannot create `.husky/_`; the commit and push gates, which run outside the sandbox, copy it from the main worktree. `.claude/state` and `.claude/worktrees` stay writable. The links in `~/.claude`, `~/.agents`, and `~/.pi/agent` are read-only, and on macOS so are their targets in the checkout, wherever it lives, so there a command cannot turn the sandbox off. `.git/hooks` is read-only in every repo under your home, on macOS only. See the known gaps below |
| Network | The listed hosts pass, including the Docker Hub auth, registry, and blob hosts for image pulls, and `*.blob.core.windows.net`, where GitHub serves Actions logs for `gh run view --log-failed`. A new host prompts once. `allowLocalBinding` and `allowAllUnixSockets` let tools such as tflint plugins open local sockets. `enableWeakerNetworkIsolation` lets Go tools such as `gh` verify TLS certificates |
| Escapes | None. `docker` stays sandboxed, but see the socket gap below |
| Node | `NODE_USE_ENV_PROXY=1` makes Node's built-in `fetch` use the sandbox proxy. Without it, tools such as `npx ctx7` fail with `fetch failed` |

### Known gaps

- `allowAllUnixSockets` lets a command connect to any Unix socket, including the Docker socket. A container can mount any host path, so `docker` is a way out of the sandbox. tflint plugins need the setting.
- `.git/config` is read-only. `git switch -c <branch> origin/main`, `git push -u`, and `git branch -u` fail because they write upstream tracking. Use `git switch -c <branch> --no-track origin/main` and `git push origin <branch>`.
- A command can read `~/.config/gh/hosts.yml`, which holds your `gh` token, and `~/.gitconfig`.
- The sandbox matches only a leading `*.` wildcard, so the Actions log hosts come in as `*.blob.core.windows.net`. A command can send data to any Azure storage account there, as it already can through the allowed GitHub hosts.
- `ps` fails with `operation not permitted`, so a session cannot check whether a process it did not start is still running. Run `ps` yourself.
- macOS `mktemp` without a template ignores `TMPDIR` and writes under `/var/folders`, which the sandbox refuses. An `allowWrite` entry with a wildcard mid-path has no effect there. Give scripts a template: `mktemp -d "${TMPDIR:-/tmp}/<name>.XXXXXX"`.
- A command can write `<git-dir>/verify-passed`, so a repo's own verify script can record its pass there. The PR gate ignores that file. It reads `<git-dir>/agent-verify-passed`, which only the `post-verify-stamp.sh` hook writes.
- On Linux the sandbox does not follow links and the `~/dev/**` and `~/**/.git/hooks` protections do not apply. Any session can then plant a `.husky` hook, a `.git/hooks` script, or a `.claude/settings.json` in any repo under `~/dev`. When the config checkout lives under `~/dev`, any session can also rewrite its `settings.json` and hooks.
- `~/.npm` stays writable, because npm needs it. A command can change a cached package under `~/.npm/_npx`, and your next `npx` outside the sandbox runs it. The rest of `~/.cache`, such as `~/.cache/pre-commit`, stays read-only for the same reason. The `CLAUDE_ENV_FILE` preamble points `XDG_CACHE_HOME` at `~/.cache/agent`, the only writable cache dir. Your own tools never read it, so a poisoned entry or a hook planted in a cached clone there reaches only agent commands. A `!` command you type in a session may source the same preamble and use that cache too.
- On Linux, a tool that keeps downloads under `XDG_CACHE_HOME`, such as test browsers, no longer finds your copy in an agent session. Its first agent run downloads again into `~/.cache/agent`, and the download host may need the network allowlist. macOS tools use `~/Library/Caches` and are unaffected.
- A worktree outside both the working directory and `~/dev` is not writable.

### gcloud for agents

Agents never use your gcloud login. A `SessionStart` hook sets `CLOUDSDK_CONFIG` to `~/.config/gcloud-agent`, which holds only short-lived impersonated tokens.

1. List targets in `~/.config/gcloud-agent/targets`, one per line: `<configuration-name> <service-account-email> <project-id>`. The first is active by default. Agents cannot edit this file, so they cannot add a service account for you to mint.
2. In your own terminal, run `scripts/gcloud-agent-login.sh`. It mints a one-hour token per target.
3. Agents pick a target with `gcloud --configuration=<name>`. Run the script again when the tokens expire.

Anything that needs your own rights, such as a PAM grant or a write, you run yourself outside the agent session.

## Run from a home repo

The [home repo pattern](https://aihero.dev/the-home-repo-pattern) runs one session from a single repo, the home repo. Each task goes to a sibling repo under `~/dev` and gets its own worktree and PR there.

- Start the session in the home repo's main checkout with `claude`, not `claude -w`. A worktree-isolated session may only touch its own worktree, so it cannot reach a sibling repo.
- Reach a child repo with `/worktree --repo <path> <slug>`. It runs `~/.agents/scripts/repo-worktree.sh`, which creates `<repo>/.claude/worktrees/<slug>` and lists the repo in `~/.cache/agent/worktree-repos`. The SessionEnd cleanup hook reads that file and prunes merged worktrees in each listed repo. The session then works there with `git -C` and absolute paths. The sandbox lets a session write every repo under `~/dev`, except `.husky` and the `.claude` settings, `hooks`, `skills`, `agents`, and `commands`. The script refuses a base that tracks those paths and prints a command to run yourself with `!`.
- Subagent `isolation: "worktree"` and `EnterWorktree` create worktrees only in the launch repo. For a child repo, create the worktree first and brief the subagent to work in its path, as `/drive-fleet` does.
- Push with `git push origin <branch>`. The new branch has no upstream, and `-u` would write `.git/config`.
- Clean up a merged child worktree with `/worktree-merge <worktree-path>`.
- To load a child repo's `CLAUDE.md`, add the repo with `--add-dir <path>` and set `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`. The variable applies only to directories added with `--add-dir`.

## Keep runtime state out of commits

Claude Code and Pi write runtime keys into `settings.json`. The two `git config` lines in the [quick start](../README.md#quick-start) install a clean filter that strips them. `.gitattributes` applies the filter to `settings.json` and `pi/settings.json`.

The filter is per-clone. A clone without it commits whatever the host wrote, including the `autoMode` environment inventory. `scripts/config-integrity.sh` fails the build when that reaches a commit and prints the fix.

## Scope a machine

These variables change what the bootstrap links:

| Variable | Default | Sets |
| --- | --- | --- |
| `AGENT_CONFIG_REPO` | `CLAUDE_DOTFILES_REPO` when set, then the checkout the script runs from, then `~/dev/personal/agent-config` when the script sits outside a git checkout | The repo the links point to |
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

Three paths assume the default dirs:

- The hook commands in `settings.json` run only `~/.claude/hooks/...`, and the status line and herdr hook use `~/.claude/` paths only. A machine that uses only `~/.claude-personal` still needs the `~/.claude` links.
- `CLAUDE_CODE_PLUGIN_DIRS` names only `~/.claude/mods/` paths. A machine without the `~/.claude` links loads no mod.
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
- A setting or table appears twice, a root setting sits inside a table, or `tui` settings are nested or dotted with no `[tui]` table.
- The fallback list differs, or `hooks` is not `true`.

Fix the file by hand, then run `--apply` again.

It also writes `~/.codex/hooks.json`. The file sends `PreToolUse`, `PostToolUse`, `SessionStart`, and `SessionEnd` events to `hooks/lib/dispatch.sh`. Codex gets no `Notification` hook. An existing hooks file of your own needs `--adopt`. Review and trust the hooks file in Codex after each regeneration.

`hooks/deny-gate.sh` brings the deny list to Codex. It blocks Bash commands matching a `Bash` rule, edits and shell commands naming a denied path, and denied MCP tools. It adds friction, not a sandbox.

Codex runs `symlink-check.sh` at session start, but that hook checks only the Claude Code dir, and the dispatcher drops its warning. Run `bash scripts/setup-hosts.sh --check --host codex` by hand to see Codex drift.

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
| `hook-bridge` | Runs the registry hooks on Pi's `bash`, `edit`, and `write` calls, session start, and session end through `hooks/lib/dispatch.sh` |
| `drift-check` | Runs `setup-hosts.sh --check` at session start and warns on drift |
| `statusline` | Replaces the footer with folder, branch, tokens, cost, context, usage windows, and model |
| `herdr-agent-state` | Reports session state to herdr when `HERDR_ENV=1` and herdr sets its socket path and pane ID |

**`permission-gate`** turns `Read` rules into `path_read` surfaces, `Edit` and `Write` rules into `path_write`, and passes `Bash` and MCP rules through. The pinned [`@gotgenes/pi-permission-system`](https://pi.dev/packages/@gotgenes/pi-permission-system) package enforces the result. The extension writes `pi/extensions/pi-permission-system/config.json`. When it cannot refresh that file, it shows an error at session start and the package keeps the last generated policy. Separately, `hooks/deny-gate.sh` runs on Pi through `hook-bridge` and blocks shell commands that name a denied path. It also applies the `Bash` rules, after normalizing each command, because the package matches them literally.

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
