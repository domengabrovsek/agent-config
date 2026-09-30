---
name: diagram
description: "Creates or updates a drawio diagram per rules/diagrams.md, writing the source file and previewing via MCP. Falls back to mermaid only when drawio is unavailable. Use when the user says 'diagram' or '/diagram', or asks for a flowchart, architecture, sequence, or state diagram."
---

Create or update the diagram for: $ARGUMENTS

## Step 1 - Pick the format

**why-no-hook:** skill workflow guidance; each step requires understanding the surrounding context (repo, task shape, prior state).

Read `rules/diagrams.md` if uncertain.

- Use **drawio** for every diagram. `(review-time: see section note)`
- Use **mermaid** only when the drawio MCP server is unavailable in the current host. `(review-time: see section note)`

## Step 2 - Locate the doc

- Identify the doc this diagram belongs to. If `docs/` does not exist, ask the user where to put it. `(review-time: see section note)`
- Slug the topic from $ARGUMENTS or the parent doc's filename. `(review-time: see section note)`

## Step 3 - Drawio path

1. Generate drawio XML for the diagram. Use `mcp__drawio__open_drawio_xml` reference (in the tool description) for shape catalogue, edge routing, swimlanes, containers. `(review-time: see section note)`
2. Write the source to `docs/diagrams/<slug>.drawio`. `(review-time: see section note)`
3. Call `mcp__drawio__open_drawio_xml` with the XML content - opens in the browser editor for the user to review and export PNG. `(review-time: see section note)`
4. Instruct the user: `File > Export As > PNG > save to docs/diagrams/<slug>.png`. They commit both files. `(review-time: see section note)`
5. In the consuming doc, embed the PNG and describe what it shows in adjacent prose: `(review-time: see section note)`

   ```markdown
   ![<topic>](diagrams/<slug>.png)
   *Source: [`<slug>.drawio`](diagrams/<slug>.drawio)*
   ```

## Step 4 - Mermaid fallback

Only when drawio is unavailable:

1. Write the mermaid source inline in the target doc using ```` ```mermaid ```` fenced blocks (one block per diagram). `(review-time: see section note)`
2. Match diagram type to purpose: `flowchart` / `sequenceDiagram` / `stateDiagram-v2` / `erDiagram` / `classDiagram` / `gitGraph` / `journey`. `(review-time: see section note)`
3. Keep node labels short. Long descriptions go in adjacent prose. `(review-time: see section note)`
4. Note in the PR description that drawio was unavailable. `(review-time: see section note)`

## Step 5 - Drift / update

If updating an existing diagram:

- For drawio: edit the `.drawio` source, re-open via MCP, re-export PNG, replace both files. Same commit. `(review-time: see section note)`
- For mermaid: convert it to drawio. Feed the block to `mcp__drawio__open_drawio_mermaid`, save the result as `.drawio`, and replace the block with the PNG embed. `(review-time: see section note)`

## Anti-patterns

- Do not generate ASCII art instead of a real diagram. `(review-time: see section note)`
- Do not pick mermaid when drawio is available. `(review-time: see section note)`
- Do not commit a `.drawio` file without its `.png` (GitHub reviewers need the preview). `(review-time: see section note)`
- Do not ship a `.png` without its `.drawio` source (next maintainer needs to edit it). `(review-time: see section note)`
- Do not invent layout coordinates manually for drawio - rely on its auto-layout. Set node ids, labels, edges, lanes; let drawio route. `(review-time: see section note)`
