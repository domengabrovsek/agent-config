---
paths:
  - "**/docs/**"
  - "**/*.drawio"
  - "**/*.mmd"
---

# Diagram Policy

**When to apply:** creating or updating any diagram in `docs/` (flowchart, sequence, architecture, state machine, etc.).

Drawio is the diagram format. Mermaid is a fallback for hosts that cannot produce a drawio diagram.

## Drawio (default)

Use drawio for every diagram: architecture, flows, sequences, state machines, data models, and topology `(review-time: format choice)`

Drawio gives consistent styling, precise layout, swimlanes, and icons, and the source stays editable in one tool.

### File convention

For each drawio diagram:

- Source: `docs/diagrams/<topic>.drawio` (XML, the source of truth, committed) `(review-time: file-convention for drawio diagrams)`
- Render: `docs/diagrams/<topic>.png` (committed alongside so GitHub previews work) `(review-time: file-convention)`
- Reference from docs: embed the PNG with a markdown image link, then a one-line caption naming the source file. `(review-time: formatting convention)`
- Describe what the diagram shows in adjacent prose, because an agent cannot read the PNG. `(review-time: requires reading surrounding doc)`
- Keep labels short. Long descriptions go in adjacent prose. `(review-time: subjective "short")`

```markdown
![Order Lifecycle](diagrams/order-lifecycle.png)
*Source: [`order-lifecycle.drawio`](diagrams/order-lifecycle.drawio)*
```

## Mermaid (fallback only)

Use mermaid only when the drawio MCP server is unavailable in the current host `(review-time: host capability check)`

- Write inline in the doc using ```` ```mermaid ```` fenced blocks. GitHub renders natively. `(review-time: format guidance for diagram authoring)`
- Say in the PR description that the diagram is mermaid because drawio was unavailable. `(review-time: PR text)`
- Convert an existing mermaid diagram to drawio when a change edits it. `(review-time: requires knowing the diff touches the diagram)`

### Authoring via MCP

The `drawio` MCP server is configured in `.mcp.json`. The tools used here are:

- `mcp__drawio__open_drawio_xml` - paste raw drawio XML, opens in the editor `(review-time: descriptive of available tool)`
- `mcp__drawio__open_drawio_csv` - tabular import (org charts, lists) `(review-time: descriptive)`
- `mcp__drawio__open_drawio_mermaid` - mermaid input rendered through drawio (useful when converting an existing mermaid diagram to drawio) `(review-time: descriptive)`

Workflow:

1. Generate the diagram source as XML / CSV / mermaid.
2. Write it to `docs/diagrams/<topic>.drawio` (or `.csv` / `.mmd` for the latter two formats - then convert).
3. Call the matching MCP tool to preview in the browser editor.
4. Export PNG from the drawio editor (`File > Export As > PNG`) and save next to the source as `docs/diagrams/<topic>.png`. Commit both.

The `/diagram` skill automates steps 1-3.

## Forbidden

- Hand-drawn / scanned diagrams (illegible, undiffable, accessibility-hostile). `(review-time: image-content classification)`
- ASCII art for anything more than a 4-node flow (use drawio). `(review-time: counting nodes in ASCII art)`
- Embedded screenshots of UML tools other than drawio. `(review-time: image-source classification)`
- Diagrams without a captioned source link in the surrounding doc. `(review-time: requires reading surrounding doc)`

## Drift

If a diagram references code paths or APIs that have changed, update the diagram in the same PR as the code. Drawio diagrams need manual drift review, because `/document` cannot read the PNG. Keep the adjacent prose accurate so the text check catches drift.
