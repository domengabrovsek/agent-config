# Documentation

> Engineering docs for `<repo-name>`. Written for engineers reading on GitHub and for Claude agents working in the repo.

## How this is organized

Docs follow [Diataxis](https://diataxis.fr/). Each doc has exactly one job:

| Quadrant | When you're... | Where to look |
|----------|----------------|---------------|
| **Explanation** | Trying to understand *why* or *how it fits together* | [explanation/](explanation/) |
| **Reference** | Looking up an exact value, name, or signature | [reference/](reference/) |
| **How-to** | Doing a concrete task | [how-to/](how-to/) |
| **Tutorial** | Learning the system end-to-end | [tutorials/](tutorials/) |

## Conventions

- Markdown only. Diagrams are [Mermaid](https://mermaid.js.org/) in fenced blocks - GitHub renders them natively.
- Each doc opens with a 3-sentence TL;DR before any heading.
- Source files are cited with backticked relative paths: `src/foo/bar.ts`.
- Max 300 lines per doc. Split if longer.

## Index

### Explanation

<!-- list explanation/*.md here -->

### Reference

<!-- list reference/*.md here -->

### How-to

<!-- list how-to/*.md here -->

### Tutorials

<!-- list tutorials/*.md here -->

## Maintaining these docs

Use the `/document` slash command in Claude Code:

- `/document explain <topic>` - new explanation doc
- `/document reference <topic>` - new reference doc
- `/document how-to <task>` - new recipe
- `/document audit` - drift report against current code

Every code change that affects documented behavior should update the relevant doc in the same PR.
