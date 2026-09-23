# Documentation

> Engineering docs for `<repo-name>`. Written for engineers reading on GitHub and for Claude agents working in the repo.

## How this is organized

Docs follow [Diataxis](https://diataxis.fr/). Each doc has exactly one job:

| Quadrant | When you're... | Where to look |
| --- | --- | --- |
| **Explanation** | Trying to understand *why* or *how it fits together* | [explanation/](explanation/) |
| **Reference** | Looking up an exact value, name, or signature | [reference/](reference/) |
| **How-to** | Doing a concrete task | [how-to/](how-to/) |
| **Tutorial** | Learning the system end-to-end | [tutorials/](tutorials/) |
| **Decisions** | Asking *why did we choose X* | [adr/](adr/) |

## Conventions

- Markdown only. Diagrams are [Mermaid](https://mermaid.js.org/) in fenced blocks by default; complex layouts use a drawio source plus a committed PNG.
- Each doc opens with a 3-sentence TL;DR before any heading.
- Source files are cited with backticked relative paths: `src/foo/bar.ts`.
- Max 300 lines per doc. Split if longer.
- ADRs are immutable once Accepted. A new decision creates a new ADR.

## Index

### Explanation

<!-- list explanation/*.md here -->

### Reference

<!-- list reference/*.md here -->

### How-to

<!-- list how-to/*.md here -->

### Tutorials

<!-- list tutorials/*.md here -->

### Architecture Decision Records

See [adr/README.md](adr/README.md).

## Maintaining these docs

Use the `/document` slash command in Claude Code:

- `/document explain <topic>` - new explanation doc
- `/document reference <topic>` - new reference doc
- `/document how-to <task>` - new recipe
- `/document adr "<title>"` - new ADR
- `/document audit` - drift report against current code

Every code change that affects documented behavior should update the relevant doc in the same PR.
