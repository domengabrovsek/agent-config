---
name: document
description: "Creates or refreshes technical engineering docs in the current repo's /docs/ tree: Diataxis layout, mermaid diagrams, ADR support, drift audit. Use when the user says 'write docs', 'document this', 'audit the docs', or '/document'."
---

Generate or update engineering documentation for: $ARGUMENTS

This skill writes docs that are dual-audience: engineers reading on GitHub AND Claude agents reading the repo. Apply the rules below without exception.

## Subcommands

**why-no-hook:** skill workflow guidance; each step requires understanding the surrounding context (repo, task shape, prior state).

Parse the first word of `$ARGUMENTS` as the subcommand:

- `explain <topic>` - create/update `docs/explanation/<topic>.md` (the *why* and *how it fits together*) `(review-time: see section note)`
- `reference <topic>` - create/update `docs/reference/<topic>.md` (lookup tables, env vars, schemas, enums) `(review-time: see section note)`
- `how-to <task>` - create/update `docs/how-to/<task>.md` (a recipe to do one thing) `(review-time: see section note)`
- `tutorial <topic>` - create/update `docs/tutorials/<topic>.md` (learning path, onboarding) `(review-time: see section note)`
- `adr "<title>"` - draft the next-numbered ADR in `docs/adr/` `(review-time: see section note)`
- `diagram <type> <topic>` - add or update a mermaid diagram inside the matching doc `(review-time: see section note)`
- `audit` - read every `docs/**/*.md`, compare against current code, produce a drift report (read-only, no edits) `(review-time: see section note)`
- `bootstrap` - create the full `docs/` skeleton in a repo that has none yet (uses `~/.agents/templates/docs-readme.md` and `~/.agents/templates/adr.md`) `(review-time: see section note)`

If no subcommand matches, ask the user which one they meant before writing anything.

## Diataxis routing

If a topic does not clearly fit one quadrant, ask. Do not split a single topic across quadrants.

| Quadrant | Use when... | Don't use when... |
|----------|-------------|-------------------|
| explanation | Reader asks *why does this exist* or *how does this fit together* | They want to do a concrete task |
| reference | Reader needs to look up an exact value, name, or signature | They want narrative context |
| how-to | Reader has a goal and needs steps | They are still trying to understand the concept |
| tutorial | Reader is new and learning end-to-end | They already know the system |

## Quality rules (apply to every doc you write)

1. **One topic per file.** If two H1-worthy ideas appear, split into two files. `(review-time: see section note)`
2. **Lead with TL;DR** in 3 sentences or fewer, before any heading. Body expands. `(review-time: see section note)`
3. **Cite source files** with backticked relative paths (`src/foo/bar.ts`). Link, do not paste. Inline code blocks longer than 15 lines are forbidden - link to the file instead. `(review-time: see section note)`
4. **Tables over prose** for any list of more than 3 parallel items. `(review-time: see section note)`
5. **Diagrams for relationships only.** No diagram if a 3-row table conveys it. Mermaid by default; drawio for complex per `rules/diagrams.md`. The `/diagram` skill picks format and writes the source. `(review-time: see section note)`
6. **Why before how.** Every explanation doc opens with the problem the thing solves. `(review-time: see section note)`
7. **No forward-looking content.** Document only behavior that exists now. No "we plan to", no "in the future". `(review-time: see section note)`
8. **No issue/PR/ticket numbers.** They rot. Put them in PR descriptions and git history, not docs. `(review-time: see section note)`
9. **ADRs are immutable once Accepted.** A new decision = a new ADR with `Status: Supersedes NNNN`. Never edit the body of an Accepted ADR. `(review-time: see section note)`
10. **Max 300 lines per doc.** If longer, split by sub-topic. `(review-time: see section note)`
11. **No emoji** unless the user explicitly asked for them. `(review-time: see section note)`
12. **No em dashes.** Use a regular hyphen. `(review-time: see section note)`

## Diagram conventions

Mermaid is the default. Use ` ```mermaid ` fenced blocks - GitHub renders natively. Diagram type by purpose:

- `flowchart TD` for high-level architecture and decision trees `(review-time: see section note)`
- `sequenceDiagram` for request flows, auth flows, async messaging `(review-time: see section note)`
- `erDiagram` for data models `(review-time: see section note)`
- `stateDiagram-v2` for state machines (order status, sync status) `(review-time: see section note)`
- `flowchart LR` with subgraphs for C4-context (services, queues, datastores) `(review-time: see section note)`

Keep node labels short. Long descriptions go in adjacent prose. One diagram per doc maximum unless the doc is explicitly an architecture overview.

Switch to drawio when the diagram needs custom shapes, cloud icons, >2 swimlanes, multi-layer architecture, or precise layout. Source lives at `docs/diagrams/<topic>.drawio` with a committed PNG at `docs/diagrams/<topic>.png` (GitHub previews need the PNG; maintainers need the source). Embed via:

```markdown
![<topic>](diagrams/<topic>.png)
*Source: [`<topic>.drawio`](diagrams/<topic>.drawio)*
```

Use the `/diagram` skill (or `mcp__drawio__*` tools directly) to author drawio diagrams. Full policy in `rules/diagrams.md`.

## File layout the skill produces or expects

```text
<repo>/
  docs/
    README.md             # index grouped by Diataxis quadrant
    explanation/
    reference/
    how-to/
    tutorials/
    adr/
      README.md           # ADR index, table of {NNNN, title, status, date}
      NNNN-<slug>.md
    diagrams/             # optional shared .mmd snippets, only if reused
```

## ADR procedure

This subcommand is the only path that creates an ADR. No other workflow proposes one.

When `adr "<title>"`:

1. Gate check: the decision must be hard to reverse, surprising without context, and a real trade-off. If a criterion fails, name it in one sentence, then write only after the user confirms. `(review-time: see section note)`
2. Convention scan: look for an existing ADR scheme (directory, numbering, headings). An existing scheme wins; steps 3-5 apply only when none exists. `(review-time: see section note)`
3. Scan `docs/adr/` for highest existing number. New file = `NNNN-<kebab-title>.md`, zero-padded to 4 digits. `(review-time: see section note)`
4. Use `~/.agents/templates/adr.md` as the body. Fill `<Title>`, today's date, status `Proposed`. `(review-time: see section note)`
5. Append a row to `docs/adr/README.md` table. `(review-time: see section note)`
6. Ask the user for Context, Decision, Consequences before finalizing - never invent a decision. `(review-time: see section note)`

## Audit procedure

When `audit`:

1. Walk `docs/**/*.md`. `(review-time: see section note)`
2. For each doc, extract source-file citations (backticked paths). Verify they exist with `Glob`/`Read`. Report missing files. `(review-time: see section note)`
3. For each ADR, verify `Status` is one of {Proposed, Accepted, Superseded by NNNN, Deprecated}. Flag malformed ADRs. `(review-time: see section note)`
4. For each `docs/reference/*.md`, scan referenced enums/configs (e.g. `src/**/enums/*.ts`) and report mismatches between doc tables and code. `(review-time: see section note)`
5. Report doc files exceeding 300 lines. `(review-time: see section note)`
6. Report any `docs/**/*.md` not linked from `docs/README.md`. `(review-time: see section note)`
7. Output a report only - do NOT edit files. The user runs targeted subcommands afterward to fix drift. `(review-time: see section note)`

## CLAUDE.md integration

After bootstrapping or significant doc changes, update the repo's `CLAUDE.md` so it points to `docs/README.md` in its Documentation section. This keeps Claude's auto-discovery working.

## Verification before finishing

- `markdownlint-cli2 docs/**/*.md` if the repo has it configured (check for `.markdownlint*` files). `(review-time: see section note)`
- All mermaid blocks are syntactically valid (rough check: balanced fences, recognized diagram type). `(review-time: see section note)`
- All source-file citations resolve. `(review-time: see section note)`
- The doc fits the quality rules above. `(review-time: see section note)`

If any check fails, fix it before reporting done.

## Out of scope

- Generated API references (Swagger/OpenAPI, TypeDoc) - separate tooling. `(review-time: see section note)`
- Product specs - those live in their own repo / system. `(review-time: see section note)`
- Anything outside `docs/` in the current repo. `(review-time: see section note)`
