# /document reference

Skill defaults and templates for `SKILL.md`. A default applies only where the repo states no convention of its own. A finding based on a default says so.

## Diataxis routing

The default layout when a repo states none. One quadrant per topic. Ask when a topic fits none.

| Quadrant | Use when... | Don't use when... |
| --- | --- | --- |
| explanation | Reader asks *why does this exist* or *how does this fit together* | They want to do a concrete task |
| reference | Reader needs to look up an exact value, name, or signature | They want narrative context |
| how-to | Reader has a goal and needs steps | They are still trying to understand the concept |
| tutorial | Reader is new and learning end-to-end | They already know the system |

## Default file layout

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
    diagrams/             # drawio sources and exported PNGs
```

## Default quality rules

1. One topic per file. Two H1-worthy ideas become two files.
2. Lead with a TL;DR of 3 sentences or fewer, before any heading.
3. Cite source files with backticked relative paths. Link, do not paste. No inline code block over 15 lines.
4. Tables over prose for more than 3 parallel items.
5. Diagrams for relationships only. No diagram when a 3-row table conveys it.
6. Why before how. An explanation opens with the problem the thing solves.
7. Present tense. Document behavior that exists now. No plans, no history of how the code got here.
8. No issue, PR or ticket numbers. They belong in PR descriptions and git history.
9. ADRs are immutable once Accepted. A new decision gets a new ADR, and the old one becomes `Superseded by NNNN`.
10. Max 300 lines per doc. Split longer docs by sub-topic.
11. No emoji unless the user asked for them.
12. No em dashes.

## Diagram conventions

Mermaid is the default, in fenced blocks GitHub renders natively. Pick the type by purpose:

| Purpose | Mermaid type |
| --- | --- |
| Architecture, decision trees | `flowchart TD` |
| Request, auth and async flows | `sequenceDiagram` |
| Data models | `erDiagram` |
| State machines | `stateDiagram-v2` |
| Services, queues, datastores | `flowchart LR` with subgraphs |

Keep node labels short and put detail in adjacent prose. One diagram per doc unless the doc is an architecture overview. Every diagram gets adjacent text naming what it shows, because an agent cannot read a drawio PNG.

Switch to drawio for custom shapes, cloud icons, more than two swimlanes, stacked layers, or precise layout. Source goes in `docs/diagrams/<topic>.drawio` with a committed PNG beside it:

```markdown
![<topic>](diagrams/<topic>.png)
*Source: [`<topic>.drawio`](diagrams/<topic>.drawio)*
```

The `/diagram` skill picks the format and writes the source. Full policy: `rules/diagrams.md`.

## ADR files

For repos that keep one file per decision.

1. An existing scheme wins: directory, numbering, headings, statuses.
2. With no scheme, scan `docs/adr/` for the highest number. The new file is `NNNN-<kebab-title>.md`, zero-padded to 4 digits.
3. Use `~/.agents/templates/adr.md` as the body. Fill the title, today's date and status `Proposed`.
4. Append a row to the `docs/adr/README.md` table.
5. Valid statuses: Proposed, Accepted, Superseded by NNNN, Deprecated.

## Bootstrap templates

- `~/.agents/templates/docs-readme.md` becomes `docs/README.md`.
- `~/.agents/templates/adr-readme.md` becomes `docs/adr/README.md`.
- `~/.agents/templates/adr.md` is the ADR body.
