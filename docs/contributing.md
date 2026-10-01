# Contributing

Every change lands through a pull request to `main`, and CI runs the same checks you can run locally. The hosts link to the checkout, so a change is live on your machine as soon as the file changes.

## Before you edit

- **Edits are live.** Every linked host sees a change in the main checkout at once. Work in a worktree to keep an unfinished change out of other sessions.
- **Run setup from the main checkout.** `setup-hosts.sh` links the repo it runs from. Run in a worktree, it points your hosts at that worktree. Set `AGENT_CONFIG_REPO` to run it elsewhere.
- **Hooks run from the project first.** A session in this repo runs its own `hooks/` copy. Open a session in your worktree to try a hook change.

## Add a rule

1. Write the rule in the `rules/` file for its topic, or in a new file. End each bullet with its [enforcement tag](rules.md#enforcement-tags).
2. Add `paths:` frontmatter when the rule applies only to some files. A rule without it loads in every Claude Code session.
3. Add a row to the routing table in `skills/rulebook/SKILL.md` for a new file, so Codex and Pi can find it.
4. Run `./scripts/config-budget.sh`. If the always-loaded surface passes its budget, scope the rule, move it into a skill, or back it with a hook.

## Add a hook

1. Write `hooks/<name>.sh`. Exit 2 with a message on stderr to block; exit 0 to allow. Read a `SKIP_<NAME>` variable if a human may need to bypass it.
2. Register it in `settings.json` under its event, with a `matcher`, an optional `if` pattern, and a timeout. Copy the command wrapper of an existing entry, so the project's copy wins over `~/.claude/hooks`.
3. Add `tests/<name>.sh`, and add a step that runs it to the `shell-tests` job in `.github/workflows/pull-request.yml`.
4. Change the tag of the rule it backs to `(hook)`.
5. If you use Codex, run `bash scripts/setup-hosts.sh --apply --host codex` from the main checkout once the change is there. The generated `hooks.json` sums the hook timeouts of each event, so it goes stale when the registry changes.

[Hooks](hooks.md) describes the registry format and how `dispatch.sh` runs it on Codex and Pi.

## Add a skill

1. Read `skills/write-a-skill/SKILL.md`, then write `skills/<name>/SKILL.md`. The `description` decides when the model loads it.
2. Set `disable-model-invocation: true` only when the skill should start by typed command alone.
3. Name shared files as `~/.agents/...`, never `~/.claude/...`. `tests/shared-paths.sh` fails when such a path does not exist in the checkout.
4. Add the skill to the [cheatsheet](../CHEATSHEET.md) and to the catalog in [skills](skills.md).

## Add a persona

1. Write `agents/<name>.md` with the sections in [agents](agents.md#agent-structure). Tag each guardrail `(persona)`.
2. Leave out `tools:` for a writer. List tools without Edit and Write for an advisory persona.
3. Add a routing row to `rules/agent-routing.md`, then run `./scripts/config-budget.sh`, because that rule loads in every session.
4. Add the persona to the tables in [agents](agents.md).

## Change the deny list

1. Edit `permissions.deny` in `settings.json`.
2. Start a Pi session, or ask a Pi user to. The `permission-gate` extension rewrites `pi/extensions/pi-permission-system/config.json`.
3. Commit that file too. `npm test` compares it with the policy derived from `settings.json`, byte for byte.

## Change host wiring

Edit `scripts/setup-hosts.sh`, update the link tables in [setup](setup.md), and run `bash tests/setup-hosts.sh`. The test uses a throwaway `HOME`, so it never touches your real config.

## Run the checks

CI runs these jobs on every pull request. Each job except Lint Markdown runs locally from the repo root.

| CI job | Local command | Checks |
| --- | --- | --- |
| Lint Markdown | none; CI uses the shared markdownlint action | Every `*.md` file against `.markdownlint.json` |
| Config Budget | `./scripts/config-budget.sh` | The always-loaded word and tag budgets |
| Prose Gate | `bash hooks/prose-gate.test.sh` | Gate fixtures, then every tracked Markdown file |
| Extension Tests | `npm test` | `tests/*.test.ts`: the deny gate and the Pi extensions |
| Config Integrity | `./scripts/config-integrity.sh` and `./scripts/shellcheck-all.sh` | JSON parses, no runtime keys committed, the git filter declared, shell lint |
| Shell Tests | `for t in tests/*.sh; do bash "$t"; done` | Host setup, drift check, shared paths, dispatcher, and every gate |

- The agent push gate runs only part of this table. `package.json` declares only a `test` script, so `pre-push-gate.sh` runs `npm test` and a critical-only `npm audit`. Run every command in the table before you push.
- The push gate blocks a push from any Node checkout without `node_modules`, even though `npm test` here needs no install. Run `npm ci` in a new worktree first.
- `shellcheck-all.sh` installs `shellcheck` through `apt-get` or `brew` when it is missing.
- `npm test` needs Node.js 22.19 or later and no install step.
- A `Gate` job passes only when every job above passed or was skipped. Branch protection requires `Gate`, so the required check stays stable when jobs change.

## Review and notifications

- **Reviewer.** `.github/workflows/reviewer.yml` calls the [shared reviewer](https://github.com/domengabrovsek/github-actions/blob/main/docs/workflows/reviewer.md). Claude reviews a PR when it opens, updates, or turns ready, comments inline, and answers the owner's replies in its threads. A fork PR gets one review each time the owner adds the `safe-to-review` label. The Claude token comes from AWS SSM through the role in the `REVIEWER_ROLE_ARN` variable, so the repo stores no secret.
- **Notifications.** A repo webhook, managed outside this repo, sends PR, review, and comment events to Telegram. New pushes to an open PR send no ping.
