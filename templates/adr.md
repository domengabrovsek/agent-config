# <Decision stated as a sentence>

## Status

Proposed - YYYY-MM-DD

## Context

What problem forced the decision. Constraints that shaped it. What was tried before, if anything. Keep to one or two paragraphs.

## Decision

The chosen option, stated plainly in one or two sentences. No hedging.

## Consequences

What this commits us to. Group as Positive / Negative / Neutral if it helps. Be honest about the downsides.

## Considered alternatives

Each alternative in one short paragraph: what it was, why it was rejected. Keep this section tight - the goal is to show the decision was not accidental, not to write a survey.

---

## Conventions

The title is the decision itself, not a label: "Share agent configuration across hosts", not "ADR 0008: Host sharing". The number lives in the filename, `NNNN-kebab-title.md`.

## Status values

- **Proposed** - written but not yet adopted.
- **Accepted** - adopted and in force. Body is now immutable; revise only typos.
- **Superseded by NNNN** - replaced by a later ADR. Keep the file in place; do not delete.
- **Deprecated** - no longer applies, no replacement. Rare.

A new decision that reverses an Accepted ADR creates a new ADR; the old one's status flips to `Superseded by <new NNNN>` and nothing else in its body changes.
