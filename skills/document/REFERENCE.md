# /document reference

Skill defaults and templates for `SKILL.md`. A default applies only where the repo states no convention of its own. A finding based on a default says so.

## Diataxis routing

The default layout when a repo states none. One quadrant per topic. Ask when a topic fits none or several, and never split a topic across quadrants.

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
9. Max 300 lines per doc. Split longer docs by sub-topic.
10. No emoji unless the user asked for them.
11. No em dashes.

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

## check: changed symbols

A changed symbol is a name the diff adds, removes or renames, or a name whose definition or value the diff changes.

Sensitive paths no subcommand reads and `check` never diffs: `.env*`, `*.pem`, `*.key`, `credentials.json`, `service-account*.json` and `*.tfstate*`. `check` drops them from the changed-path list by name. Excluding them with a pathspec names a denied pattern, which the host's deny gate blocks.

| Kind | Where the diff shows it |
| --- | --- |
| Env var | Config schema, code that reads it |
| Table or column | Schema files, migrations |
| Route | Controller decorators, router files |
| Enum or closed value | Union types, constant arrays, check constraints |
| Config key | Config schemas, `*.tfvars`, manifests such as `stack.hcl` |
| CLI flag or script | Package scripts, flags passed in workflows or scripts |
| Stack, module or resource | The unit whose files the diff changes |
| Workflow or job | `.github/workflows/*` file and job names |
| IAM role, grant or principal | Role bindings, service accounts, access policies |

## check: report template

```markdown
## Docs check: <base>..working tree

### Corrected
| Doc:line | Was | Now | Evidence |

### Decisions, controls and compliance mappings the change contradicts
| Doc:line | Statement | Contradicting change |

### Coverage gaps
| Changed behavior | Evidence | Doc that should cover it |

### Not verified
| Doc:line | Claim | Why it was left |

### Outside the docs scope
| File:line | Stale claim | Suggested fix |

### Still accurate
<n> matched passages in <m> docs.
```

## audit: report template

One row per doc, finding type and shared evidence, with the full doc path and every line on it. A row names exactly one file, never a glob, a directory or a count of docs. Quote a link target as written. Write "None" under an empty heading.

```markdown
## Docs audit: <repo> at <sha>

Conventions read: <files>
Checks run: <commands, or "not run" and why>

### Access and security claims
| Doc:lines | Claim | What the code allows |

### Broken links and anchors
| Doc:line | Target | Evidence |

### Unchecked external links
| Doc:line | URL |

### Stale facts
| Doc:line | Claim | What the code says |

### Convention breaks
| Doc:line | Finding | Rule broken (quoted) |

### Length
| Doc | Lines | Cap (quoted repo rule, or "skill default: 300") |

### Unindexed docs
| Doc | Nearest index |

### Decision records
| Doc:line | Finding | Scheme the repo uses |

### Not verified
| Doc or area | Why it was left |
```

## audit: GitHub links

Drop any `#fragment` first, and list the anchor as unchecked. Before any call, check the owner, repo, ref and path against letters, digits and `._/-`, and the number against digits. Reject a link with a `.` or `..` path segment or a percent sign, and list it as unchecked.

| Link shape | Endpoint |
| --- | --- |
| `github.com/<owner>/<repo>` | `repos/<owner>/<repo>` |
| `github.com/<owner>/<repo>/blob/<ref>/<path>` or `/tree/<ref>/<path>` | `repos/<owner>/<repo>/contents/<path>?ref=<ref>` |
| `github.com/<owner>/<repo>/pull/<n>` or `/issues/<n>` | `repos/<owner>/<repo>/issues/<n>` |
| Any other shape | None; list the link as unchecked |

Call `gh api --method GET '<endpoint>'`, with the endpoint single-quoted and no `-f` or `-F`. Keep only the HTTP status.

## review: report template

```markdown
## Doc review: <doc path>

### Reader test
| Question | Result (answered, partly answered, not answered, or skipped) | What the reader lacked |

### Prune candidates
| Lines | Reason (restates the code, history, filler, or duplicates <doc>) | Note |

### Diagram verdict
<needed and missing | present and current | present and stale | not needed>: <the relationship behind the verdict>
| Node or edge | What the code says |

### Stale facts
| Line | Claim | What the code says |

### Consistency with repo conventions
| Line | Finding | Rule broken (quoted) |
```

## ADR files

For repos that keep one file per decision. With an existing scheme, follow its directory, numbering, headings, statuses and index, and skip the steps below.

With no scheme:

1. Scan `docs/adr/` for the highest number. The new file is `NNNN-<kebab-title>.md`, zero-padded to 4 digits.
2. Use `~/.agents/templates/adr.md` as the body. Fill the title, today's date and status `Proposed`.
3. Append a row to the `docs/adr/README.md` table.
4. Use these statuses: Proposed, Accepted, Superseded by NNNN, Deprecated.

## Bootstrap templates

- `~/.agents/templates/docs-readme.md` becomes `docs/README.md`.
- `~/.agents/templates/adr-readme.md` becomes `docs/adr/README.md`.
- `~/.agents/templates/adr.md` is the ADR body.
