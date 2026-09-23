---
paths:
  - "**/docs/**"
  - "**/*.drawio"
  - "**/*.mmd"
---

# Diagram Policy

**When to apply:** creating or updating any diagram in `docs/` (flowchart, sequence, architecture, state machine, etc.).

Two diagram formats are allowed in `docs/`. Pick by complexity, not by aesthetic preference.

## Mermaid (default)

Use mermaid for diagrams whose value is the **logical structure**, where a clean text representation suffices and reviewers benefit from GitHub's native rendering.

Mermaid is correct when:

- Sequence flows (request lifecycle, auth, async messaging) `(review-time: diagram-type classification)`
- State machines (order status, sync status) `(review-time: diagram-type classification)`
- ER diagrams (data models) `(review-time: diagram-type classification)`
- Class diagrams `(review-time: diagram-type classification)`
- Simple flowcharts and decision trees `(review-time: diagram-type classification)`
- Graph/topology with <15 nodes and standard shapes `(review-time: requires diagram analysis)`
- gitGraph, journey, gantt, pie `(review-time: diagram-type classification)`

How:

- Write inline in the doc using ```` ```mermaid ```` fenced blocks. GitHub renders natively. `(review-time: format guidance for diagram authoring)`
- One diagram per doc maximum, unless it is an architecture doc. `(review-time: doc-classification "architecture")`
- Keep labels short - long descriptions go in adjacent prose. `(review-time: subjective "short")`

## Drawio (for complex)

Use drawio when mermaid genuinely fails the diagram. Reach for drawio when:

- Precise grid / column layout matters (network topology, rack diagrams) `(review-time: diagram-complexity judgment)`
- Custom shapes / icons / cloud provider symbols are required `(review-time: diagram-complexity judgment)`
- Swimlanes with >2 lanes or nested swimlanes `(review-time: diagram-complexity judgment)`
- Multi-layer architecture (data plane + control plane stacked) `(review-time: diagram-complexity judgment)`
- Color and styling carry semantic weight that mermaid styling cannot express cleanly `(review-time: diagram-complexity judgment)`
- Interactive editing is expected post-merge (cross-team architecture review) `(review-time: workflow choice)`

If you find yourself fighting mermaid syntax for layout reasons, switch to drawio - that's the signal.

### File convention

For each drawio diagram:

- Source: `docs/diagrams/<topic>.drawio` (XML, the source of truth, committed) `(review-time: file-convention for drawio diagrams)`
- Render: `docs/diagrams/<topic>.png` (committed alongside so GitHub previews work) `(review-time: file-convention)`
- Reference from docs: embed the PNG with a markdown image link, then a one-line caption naming the source file. `(review-time: formatting convention)`

```markdown
![Order Lifecycle](diagrams/order-lifecycle.png)
*Source: [`order-lifecycle.drawio`](diagrams/order-lifecycle.drawio)*
```

### Authoring via MCP

The `drawio` MCP server is configured in `.mcp.json`. The tools used here are:

- `mcp__drawio__open_drawio_xml` - paste raw drawio XML, opens in the editor `(review-time: descriptive of available tool)`
- `mcp__drawio__open_drawio_csv` - tabular import (org charts, lists) `(review-time: descriptive)`
- `mcp__drawio__open_drawio_mermaid` - mermaid input rendered through drawio (useful when you want a richer-styled version of an existing mermaid diagram) `(review-time: descriptive)`

Workflow:

1. Generate the diagram source as XML / CSV / mermaid.
2. Write it to `docs/diagrams/<topic>.drawio` (or `.csv` / `.mmd` for the latter two formats - then convert).
3. Call the matching MCP tool to preview in the browser editor.
4. Export PNG from the drawio editor (`File > Export As > PNG`) and save next to the source as `docs/diagrams/<topic>.png`. Commit both.

The `/diagram` skill automates steps 1-3.

## Forbidden

- Hand-drawn / scanned diagrams (illegible, undiffable, accessibility-hostile). `(review-time: image-content classification)`
- ASCII art for anything more than a 4-node flow (use mermaid). `(review-time: counting nodes in ASCII art)`
- Embedded screenshots of UML tools other than drawio. `(review-time: image-source classification)`
- Diagrams without a captioned source link in the surrounding doc. `(review-time: requires reading surrounding doc)`

## Drift

If a diagram references code paths or APIs that have changed, update the diagram in the same PR as the code. The `/document` workflow handles drift detection for mermaid diagrams; drawio diagrams need manual review since the editor pipeline is offline.
