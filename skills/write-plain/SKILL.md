---
name: write-plain
description: "Edits prose to cut the patterns that read as machine-written: puffery, vague attribution, forced triads, synonym cycling, inline-header lists, and sentences that name a feeling instead of a mechanism. Use when writing or revising a doc, ADR, spec, research artifact, PR description, or any prose longer than a few lines."
---

> Source: [cursor/plugins - pstack/skills/unslop](https://github.com/cursor/plugins/blob/main/pstack/skills/unslop/SKILL.md). Adapted, not vendored verbatim; see "What this skill leaves out" below.

The mechanical half of this policy is a hook, not a skill. `hooks/prose-gate.sh` blocks the word list, the filler phrases, the chatbot artifacts, curly quotes and emoji headings on every markdown write, commit message and PR body. Nothing in this file repeats that list.

This skill covers what a regex cannot see.

## Process

1. Read the draft against the patterns below.
2. Rewrite. Keep the meaning, keep the register.
3. Ask what a reader does with each sentence. If a sentence supports no action, no decision, and no fact, cut it.

## Patterns

### Say what it does, not how it feels

"The database stays close at hand", "SQL you can read", "types that follow your schema" all name a feeling. Name the mechanism or a number instead: "`.toSQL()` returns the exact string sent to the database", "a column rename fails the build".

Two checks:

- Restate the sentence as an instruction, a fact, or a number. If you cannot, cut it.
- If the sentence could appear unchanged in another project's docs, it says nothing about this one. Cut it.

### Puffery and promotion

"a pivotal moment", "a testament to", "the evolving landscape", "setting the stage for". Cut the frame, state what happened. Same for "nestled", "breathtaking", "groundbreaking", "renowned", "must-visit" in any description that should be neutral.

### Vague attribution

"Experts believe", "industry reports suggest", "some critics argue". Name the source with a link, or delete the claim. This is the prose form of "Verify before asserting" in `AGENTS.md`: cite the file, the command output, or the query.

### Superficial -ing clauses

A trailing "..., highlighting the need for X", "..., ensuring reliability", "..., reflecting the team's priorities" adds no information. Delete it, or replace it with the specific consequence.

### Forced triads

Three items because three sounds complete, not because there are three. Use the real number. Two is a fine list. So is five.

### Synonym cycling

Protagonist, main character, central figure, hero across one section. Pick the term and repeat it. In this repo the glossary in `CONTEXT.md` decides which term wins; check it before inventing a second name for something already named.

### False ranges

"from X to Y" where X and Y sit on no shared scale: "from authentication to deployment". List the items instead.

### Inline-header lists

The tell is a bold label whose colon restates the line: "**Performance:** Performance improved by 20%". Convert to prose.

A bold lead-in that ends in a period, names the item, and is followed by genuinely new detail is fine and not a tell: "**Schema in TypeScript.** Tables live in one file."

### Not just X, but Y

State the point directly. The construction promises a reversal it rarely delivers.

### Stacked hedging

"could potentially possibly be argued that it might" is one hedge wearing four coats. Pick one, or drop all of them and make the claim.

### Colons as connectors

A colon before a list or an example is correct. A colon splicing two independent clauses is a crutch: it implies a relationship the sentence never states. Rewrite so the point stands without it.

This one is judgment, not a rule, because the `term: definition` shape used throughout `rules/` is a legitimate colon and a regex cannot tell the two apart.

### Generic conclusions

"The future looks bright", "this sets us up well". State the next specific step or end the document. A closing paragraph that repeats the opening is filler, which "Write plain" in `AGENTS.md` already rules out.

## What this skill leaves out

Recorded so a future re-vendor does not silently reintroduce these.

- **The "Adding soul" section.** Two of its six items already exist here in stronger form: "have opinions" is `rules/communication.md` (lead with your recommendation), "be specific" is "Verify before asserting" in `AGENTS.md` (cite the file and line). The other four ("vary rhythm", "let some mess in", "acknowledge complexity", "use I") contradict the length caps and the one-idea-per-sentence rule in "Write plain" in `AGENTS.md`. The output surfaces here are commit messages, ADRs, PR bodies and chat replies, where terse is the correct register.
- **Sentence-case headings.** The convention here is title case for document titles and sentence case for ADR decision statements, which are sentences. Adopting the upstream rule would rename 36 headings for no gain in clarity.
- **Four words from the upstream lists.** `surface`, `features`, `vector` and `harness` are terms of art in this repo, so `hooks/prose-gate.sh` does not check them.
