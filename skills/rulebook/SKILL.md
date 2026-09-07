---
name: rulebook
description: "Routes agent hosts to the applicable detailed standards in this repo's rules directory. Use before implementation, review, documentation, Git operations, delegation, or other work that needs rules beyond AGENTS.md."
---

# Rulebook

Load detailed standards for the current task from `rules/`. Read only the relevant files from the routing table. Do not read every rule by default.

The `rules/` tree sits beside the `skills/` tree in the agent-config checkout, so it resolves as `../../rules/` from this file. Claude Code also reaches it at `~/.claude/rules/`.

## Routing

| Task or context | Read |
| --- | --- |
| Any implementation | `rules/engineering-principles.md` |
| Editing code comments | `rules/comments.md` |
| Editing TypeScript | `rules/typescript.md` |
| Editing or designing tests | `rules/tests.md` |
| Editing migrations, schemas, queries, or database code | `rules/database.md` |
| Editing infrastructure, CI/CD, containers, or running infrastructure commands | `rules/infrastructure.md` |
| Creating or updating diagrams | `rules/diagrams.md` |
| Writing or editing rules, agent instructions, personas, or skills | `rules/rule-authoring.md` and `rules/communication.md` |
| Committing, branching, pushing, or opening a pull request | `rules/git-conventions.md` |
| Using teammates or splitting parallel work | `rules/agent-routing.md` and `rules/parallel-agents.md` |
| Saving research, plans, specs, or session diaries | `rules/state-persistence.md` |
| Working from a Jira reference | the `jira` skill |
| Answering about a library, framework, SDK, API, CLI, or cloud service | `rules/context7.md` |
| User communication not already covered by shared guidance | `rules/communication.md` |

Read combinations when the task crosses rows. For example, a TypeScript database change with tests needs the implementation, TypeScript, database, and test rules.

After loading the matching files, follow them as the detailed source of truth. If a rule names a host-specific capability, apply the compatibility mapping in the root `AGENTS.md`.
