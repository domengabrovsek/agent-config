---
name: improve-codebase-architecture
description: "Finds deepening opportunities in a codebase, informed by the domain language in CONTEXT.md and the repo's documented decisions. Use when the user wants to improve architecture, find refactoring opportunities, consolidate tightly-coupled modules, or make a codebase more testable and AI-navigable."
---

> Source: [mattpocock/skills - engineering/improve-codebase-architecture](https://github.com/mattpocock/skills/tree/main/skills/engineering/improve-codebase-architecture)

# Improve Codebase Architecture

Surface architectural friction and propose **deepening opportunities** - refactors that turn shallow modules into deep ones. The aim is testability and AI-navigability.

## Glossary

**why-no-hook:** skill workflow guidance; each step requires understanding the surrounding context (repo, task shape, prior state).

Use these terms exactly in every suggestion. Consistent language is the point - don't drift into "component," "service," "API," or "boundary." Full definitions in [LANGUAGE.md](LANGUAGE.md).

- **Module** - anything with an interface and an implementation (function, class, package, slice). `(review-time: see section note)`
- **Interface** - everything a caller must know to use the module: types, invariants, error modes, ordering, config. Not just the type signature. `(review-time: see section note)`
- **Implementation** - the code inside. `(review-time: see section note)`
- **Depth** - leverage at the interface: a lot of behaviour behind a small interface. **Deep** = high leverage. **Shallow** = interface nearly as complex as the implementation. `(review-time: see section note)`
- **Seam** - where an interface lives; a place behaviour can be altered without editing in place. (Use this, not "boundary.") `(review-time: see section note)`
- **Adapter** - a concrete thing satisfying an interface at a seam. `(review-time: see section note)`
- **Leverage** - what callers get from depth. `(review-time: see section note)`
- **Locality** - what maintainers get from depth: change, bugs, knowledge concentrated in one place. `(review-time: see section note)`

Key principles (see [LANGUAGE.md](LANGUAGE.md) for the full list):

- **Deletion test**: imagine deleting the module. If complexity vanishes, it was a pass-through. If complexity reappears across N callers, it was earning its keep. `(review-time: see section note)`
- **The interface is the test surface.** `(review-time: see section note)`
- **One adapter = hypothetical seam. Two adapters = real seam.** `(review-time: see section note)`

This skill is _informed_ by the project's domain model. The domain language gives names to good seams; documented decisions are ones the skill should not re-litigate.

## Process

### 1. Explore

Read the project's domain glossary and any documented decisions in the area you're touching first.

Then use the Agent tool with `subagent_type=Explore` to walk the codebase. Don't follow rigid heuristics - explore organically and note where you experience friction:

- Where does understanding one concept require bouncing between many small modules? `(review-time: see section note)`
- Where are modules **shallow** - interface nearly as complex as the implementation? `(review-time: see section note)`
- Where have pure functions been extracted just for testability, but the real bugs hide in how they're called (no **locality**)? `(review-time: see section note)`
- Where do tightly-coupled modules leak across their seams? `(review-time: see section note)`
- Which parts of the codebase are untested, or hard to test through their current interface? `(review-time: see section note)`

Apply the **deletion test** to anything you suspect is shallow: would deleting it concentrate complexity, or just move it? A "yes, concentrates" is the signal you want.

### 2. Present candidates

Present a numbered list of deepening opportunities. For each candidate:

- **Files** - which files/modules are involved `(review-time: see section note)`
- **Problem** - why the current architecture is causing friction `(review-time: see section note)`
- **Solution** - plain English description of what would change `(review-time: see section note)`
- **Benefits** - explained in terms of locality and leverage, and also in how tests would improve `(review-time: see section note)`

**Use CONTEXT.md vocabulary for the domain, and [LANGUAGE.md](LANGUAGE.md) vocabulary for the architecture.** If `CONTEXT.md` defines "Order," talk about "the Order intake module" - not "the FooBarHandler," and not "the Order service."

**Decision conflicts**: if a candidate contradicts a documented decision, only surface it when the friction is real enough to warrant revisiting that decision. Mark it clearly (e.g. _"contradicts the lane-mode decision - but worth reopening because…"_). Don't list every theoretical refactor a decision forbids.

Do NOT propose interfaces yet. Ask the user: "Which of these would you like to explore?"

### 3. Grilling loop

Once the user picks a candidate, drop into a grilling conversation. Walk the design tree with them - constraints, dependencies, the shape of the deepened module, what sits behind the seam, what tests survive.

Side effects happen inline as decisions are made:

- **Naming a deepened module after a concept not in `CONTEXT.md`?** Add the term to `CONTEXT.md` - same discipline as `/grill-with-docs` (see [CONTEXT-FORMAT.md](../grill-with-docs/CONTEXT-FORMAT.md)). Create the file lazily if it doesn't exist. `(review-time: see section note)`
- **Sharpening a fuzzy term during the conversation?** Update `CONTEXT.md` right there. `(review-time: see section note)`
- **User rejects the candidate with a load-bearing reason?** Record the reason in the review output so a future run does not re-suggest it. `(review-time: see section note)`
- **Want to explore alternative interfaces for the deepened module?** See [INTERFACE-DESIGN.md](INTERFACE-DESIGN.md). `(review-time: see section note)`
