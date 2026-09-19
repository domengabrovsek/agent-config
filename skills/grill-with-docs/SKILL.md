---
name: grill-with-docs
description: "Runs a grilling session that challenges a plan against the existing domain model, sharpens terminology, and updates the CONTEXT.md glossary inline as decisions are made. Use when the user wants to stress-test a plan against their project's language and documented decisions."
---

> Source: [mattpocock/skills - engineering/grill-with-docs](https://github.com/mattpocock/skills/tree/main/skills/engineering/grill-with-docs)

<what-to-do>

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback on each question before continuing.

If a *fact* can be found by exploring the codebase, look it up instead of asking. The *decisions*, though, are mine - put each one to me and wait.

Do not enact the plan until I confirm we have reached a shared understanding.

</what-to-do>

<supporting-info>

## Domain awareness

During codebase exploration, also look for existing documentation:

### File structure

Most repos have a single context:

```text
/
├── CONTEXT.md
└── src/
```

If a `CONTEXT-MAP.md` exists at the root, the repo has multiple contexts. The map points to where each one lives:

```text
/
├── CONTEXT-MAP.md
├── src/
│   ├── ordering/
│   │   └── CONTEXT.md
│   └── billing/
│       └── CONTEXT.md
```

Create files lazily - only when you have something to write. If no `CONTEXT.md` exists, create one when the first term is resolved.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y - which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose one precise term to use everywhere. "You're saying 'account' - do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible - which is right?"

### Update CONTEXT.md inline

When a term is resolved, update `CONTEXT.md` right there. Don't batch these up - capture them as they happen. Use the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

Don't couple `CONTEXT.md` to implementation details. Only include terms that are meaningful to domain experts. `CONTEXT.md` is a glossary and nothing else - not a spec, not a scratch pad.

## Panel grilling (optional)

For a plan with genuine cross-domain tension or competing approaches, convene a **panel** (see `rules/parallel-agents.md`) instead of grilling solo:

- Spawn domain-expert teammates via the Agent tool (route per `rules/agent-routing.md`), each with a read-only brief and a distinct stance to argue `(review-time: panel-vs-solo judgment)`
- Have them debate the plan among themselves via SendMessage - the cross-talk between teammates surfaces contradictions and trade-offs you would miss solo `(review-time: protocol guidance)`
- Turn their disagreement into the next question and put it to the user - keep the user-facing cadence to one question at a time per `rules/communication.md`; the panel never messages the user directly `(review-time: cadence discipline)`
- Skip the panel for single-domain plans - solo grilling is cheaper and a panel adds nothing when there is nothing to contend `(review-time: panel-vs-solo judgment)`

</supporting-info>
