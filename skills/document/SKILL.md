---
name: document
description: "Keeps a repo's technical docs accurate and consistent with its own conventions: checks the current diff against the docs it affects, audits the docs tree, reviews one doc with a fresh reader, and writes docs where the repo expects them. Use when the user says 'check the docs', 'audit the docs', 'review this doc', 'write docs', 'document this', or '/document'."
---

Keep the engineering docs accurate for: $ARGUMENTS

Docs serve two readers: engineers on GitHub and agents working in the repo. Each sentence carries a fact, a decision and its reason, a step, or a pointer. Anything else is a cut.

**why-no-hook:** skill workflow guidance for every section below; each step needs the repo's conventions, the diff, and the doc's content in view, which no hook sees.

Defaults, templates and layouts live in [REFERENCE.md](REFERENCE.md).

## Step 0: Read the repo's conventions

Run this before any subcommand.

1. Read the docs index: `docs/README.md`, or whatever the instruction file names as the index. `(review-time: see section note)`
2. Read the documentation section of `CLAUDE.md`, or `AGENTS.md` when no `CLAUDE.md` exists. `(review-time: see section note)`
3. Find the CI checks that touch docs: markdownlint config, doc invariant tests, workflow steps naming `docs/`. `(review-time: see section note)`
4. Note the layout, where decisions live, the required sections per doc type, the citation style, stated rules on tense, length and diagrams, and the check commands. `(review-time: see section note)`

- A stated repo convention overrides every skill default. `(review-time: see section note)`
- A skill default from [REFERENCE.md](REFERENCE.md) applies only where the repo states nothing, and any finding based on one says "skill default". `(review-time: see section note)`
- A repo with no `docs/` and no stated conventions gets the skill defaults; suggest `bootstrap`. `(review-time: see section note)`

## Subcommands

Parse the first word of `$ARGUMENTS`:

- `check [base]` - compare the diff with the docs it affects and correct stale facts. Base defaults to the merge-base with the default branch, plus uncommitted changes. `(review-time: see section note)`
- `audit` - read-only report on the whole docs tree. `(review-time: see section note)`
- `review <doc>` - reader test, prune candidates, diagram verdict and consistency for one doc. Report first, apply on the user's go. `(review-time: see section note)`
- `write <topic>` - create or update the doc for a topic, placed and shaped by the repo's conventions. `(review-time: see section note)`
- `adr "<title>"` - record a decision as an ADR file, in repos that keep ADR files. `(review-time: see section note)`
- `bootstrap` - create a `docs/` skeleton in a repo that has none. `(review-time: see section note)`

If no subcommand matches, ask which one the user meant before reading further.

## write

1. Find the doc that already covers the topic. Update it rather than add a second one. `(review-time: see section note)`
2. Place a new doc where the repo's layout puts that kind of doc. With no stated layout, use the Diataxis routing in [REFERENCE.md](REFERENCE.md). `(review-time: see section note)`
3. Use the repo's required sections for that doc type, in its order. `(review-time: see section note)`
4. A decision goes where the repo records decisions: a section in the doc for its concern, or an ADR file via `adr`. Follow the repo's heading and numbering style. `(review-time: see section note)`
5. Record a decision only when it is hard to reverse, surprising without context, and a real trade-off. Ask the user for the context, the decision and its consequences. Never invent one. `(review-time: see section note)`
6. Add a diagram when the topic has a flow, sequence, state machine or topology that a table cannot show. Use `/diagram` to write it. `(review-time: see section note)`
7. Add the doc to the docs index and link it from related docs. `(review-time: see section note)`

## adr

This subcommand is the only path that creates an ADR file. No other workflow proposes one.

1. Check whether the repo keeps ADR files: a directory of numbered decision files, or a stated convention. `(review-time: see section note)`
2. No ADR files, because they were retired or never used: create nothing. Tell the user where the repo records decisions, and offer `write` to add the decision there. `(review-time: see section note)`
3. ADR files: apply the decision test from `write` step 5. If a criterion fails, name it in one sentence and write only after the user confirms. `(review-time: see section note)`
4. Follow the ADR file procedure in [REFERENCE.md](REFERENCE.md). Ask the user for Context, Decision and Consequences before finalizing. `(review-time: see section note)`
5. Never edit the body of an Accepted ADR. A new decision gets a new ADR, and the old one's status becomes `Superseded by NNNN`. `(review-time: see section note)`

## bootstrap

- Refuse when `docs/` already exists, and offer `audit` instead. `(review-time: see section note)`
- Otherwise create the default layout from [REFERENCE.md](REFERENCE.md) with its bootstrap templates. `(review-time: see section note)`

## Audit procedure

When `audit`:

1. Walk `docs/**/*.md`. `(review-time: see section note)`
2. For each doc, extract source-file citations (backticked paths). Verify they exist with `Glob`/`Read`. Report missing files. `(review-time: see section note)`
3. For each ADR, verify `Status` is one of {Proposed, Accepted, Superseded by NNNN, Deprecated}. Flag malformed ADRs. `(review-time: see section note)`
4. For each `docs/reference/*.md`, scan referenced enums/configs (e.g. `src/**/enums/*.ts`) and report mismatches between doc tables and code. `(review-time: see section note)`
5. Report doc files exceeding 300 lines. `(review-time: see section note)`
6. Report any `docs/**/*.md` not linked from `docs/README.md`. `(review-time: see section note)`
7. Output a report only - do NOT edit files. The user runs targeted subcommands afterward to fix drift. `(review-time: see section note)`

## Instruction file integration

After `bootstrap` or a new top-level doc, make the repo's instruction file point to the docs index in its documentation section. Use `CLAUDE.md` when the repo has one, otherwise `AGENTS.md`. Claude Code reads `AGENTS.md` only when no `CLAUDE.md` exists, so this keeps Claude's auto-discovery working.

## Verification before finishing

- Run the repo's own doc checks found in Step 0. `(review-time: see section note)`
- With none, confirm that every source-file citation resolves and every mermaid block names a known diagram type. `(review-time: see section note)`

If a check fails, fix it before reporting done.

## Out of scope

- Generated API references (OpenAPI, TypeDoc): separate tooling owns them. `(review-time: see section note)`
- Docstrings and code comments: `rules/comments.md` governs them. `(review-time: see section note)`
- Product specs: they live in their own repo or system. `(review-time: see section note)`
