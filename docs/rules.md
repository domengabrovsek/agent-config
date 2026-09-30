# Rules

`rules/` holds 15 detailed standards that extend `AGENTS.md`. On Claude Code, nine load in every session and six load only when a touched file matches their `paths:` glob. Every rule bullet ends with a tag that names what enforces it.

## Which rules load when

Claude Code loads a rule at session start unless its frontmatter has `paths:`. A rule with `paths:` loads when the session touches a matching file.

| Rule | Loads | Covers |
| --- | --- | --- |
| `agent-routing.md` | Always | Which persona to spawn for a specialized task |
| `comments.md` | Always | When a code comment earns its place, and its format |
| `communication.md` | Always | Reply length, one question per turn, full URLs |
| `context7.md` | Always | Fetching current library docs with the `ctx7` CLI |
| `engineering-principles.md` | Always | Change size, vertical slices, and which source wins a conflict |
| `git-conventions.md` | Always | Commits, branches, pushes, and pull requests |
| `parallel-agents.md` | Always | Worktree lanes, read-only panels, and teammate limits |
| `shell-commands.md` | Always | Direct command forms instead of wrappers |
| `state-persistence.md` | Always | Where research, specs, plans, and diaries go |
| `database.md` | SQL, migrations, Prisma, Drizzle, models, repositories | Migrations, queries, and schema code |
| `diagrams.md` | `docs/`, `*.drawio`, `*.mmd` | Diagram format and file layout |
| `infrastructure.md` | Terraform, Docker, Kubernetes, Helm, Ansible, CI files | Infrastructure code and destructive infra commands |
| `rule-authoring.md` | `rules/`, `agents/`, `skills/**/SKILL.md` | How to write and tag a rule |
| `tests.md` | `*.test.*`, `*.spec.*`, `__tests__/`, `e2e/` | Test design and structure |
| `typescript.md` | `*.ts`, `*.tsx` | TypeScript types and style |

## How rules reach each host

| Host | Path | How a rule loads |
| --- | --- | --- |
| Claude Code | `~/.claude/rules` | Natively, by the table above |
| Codex | `~/.agents/rules` | The `rulebook` skill picks the rule files a task needs |
| Pi | `~/.agents/rules` | The `rulebook` skill picks the rule files a task needs |

`AGENTS.md` tells every host to use `rulebook` when a task needs a detailed standard. The skill holds a routing table from task to rule file, such as "Editing TypeScript" to `rules/typescript.md`. On Codex and Pi every rule therefore loads on demand, including the nine that Claude Code always loads.

## Enforcement tags

`rules/rule-authoring.md` requires a tag at the end of every rule bullet in `rules/`, in persona guardrails, and in skill rules. Prose, examples, and steps carry no tag.

| Tag | Enforced by | Cost of a miss |
| --- | --- | --- |
| `(hook)` | A script in `hooks/`, registered in `settings.json` | About a second; the model gets the message as a tool result |
| `(lint)` | The target repo's Biome, ESLint, or markdownlint config | One lint run |
| `(CI)` | A workflow in `.github/workflows/` | One PR cycle |
| `(persona)` | The Guardrails section of an `agents/*.md` file | Holds only inside that persona's subagent |
| `(review-time: <why>)` | Attention, from the model or a reviewer | Unbounded; it holds only while someone notices |

The table runs from most to least reliable. A rule that two layers catch takes only the stronger tag.

A `(review-time)` tag must say why no hook, linter, or CI check can catch the rule. When several bullets share one reason, a `**why-no-hook:**` paragraph under the heading states it once, and each bullet says `(review-time: see section note)`. A rule without such a reason is a candidate for a hook, or for deletion.

Moving a rule to a stronger layer changes its tag and adds the check in the same pull request.

## The budget

`scripts/config-budget.sh` caps the always-loaded surface, because every word there competes for attention in every session:

| Limit | Value | Counts |
| --- | --- | --- |
| Words | 4,010 | `AGENTS.md` plus the nine always-loaded rules |
| `(review-time` tags | 100 | The same files |

CI runs the script, and it prints a per-file word count. When a new rule would pass the limit, give it `paths:` frontmatter, move it into a skill, or back it with a hook. [Contributing](contributing.md#add-a-rule) lists the steps.

## Where else guidance lives

| Kind | Where | Loads |
| --- | --- | --- |
| Always-needed guidance | `AGENTS.md` | Every session, every host |
| Detailed standards | `rules/` | As above |
| Repeatable procedures | `skills/` | When a request matches the skill |
| Domain expertise | `agents/` | When a persona is spawned |
| Checklists | `references/` | When a skill or persona names one |
