---
name: wayfinder
description: "Plans a huge chunk of work - more than one agent session can hold - as a shared map of decision tickets in a local file, and resolves them one at a time until the way to the destination is clear. Use when the user invokes /wayfinder on an effort too big for a single session."
disable-model-invocation: true
---

> Source: [mattpocock/skills - engineering/wayfinder](https://github.com/mattpocock/skills/tree/main/skills/engineering/wayfinder), re-homed onto a local file map (this repo runs no issue tracker - see `docs/decisions.md`).

A loose idea has arrived - too big for one agent session, and wrapped in fog: the way from here to the **destination** isn't visible yet. Wayfinding is about finding that way, not charging at the destination. This skill charts the way as a **shared map** in a local file, then works its **decision tickets** - questions whose resolution is a decision, not slices of a build to execute - one at a time until the route is clear.

The destination varies per effort, and naming it is the first act of charting - it shapes every ticket. It might be a spec to hand off and iterate on, a decision to lock before planning starts, or a change made in place like a data-structure migration. The map is domain-agnostic - engineering work, infra work, whatever fits the shape.

## Plan, don't do

Wayfinder is **planning** by default: each ticket resolves a decision, and the map is done when the way is clear - nothing left to decide before someone goes and does the thing. The pull to just do the work is usually the signal you've reached the edge of the map and it's time to hand off to `/spec`. An effort can override this in its **Notes** - carrying execution into the map itself - but absent that, produce decisions, not deliverables. `(review-time: plan-vs-do judgment; the pull to execute is the hand-off signal)`

## Refer by name

Every ticket has a **name** - its heading. In everything the human reads - narration, the map's Decisions-so-far - refer to it by that name, never by a bare index or number. A wall of `#1, #2, #3` is illegible; names read at a glance. `(review-time: legibility discipline in narration)`

## The Map

The map is a single markdown file at `.claude/state/wayfinder/<effort-slug>.md` - the single source of truth. Its tickets live inside it under `## Tickets`.

The map is an **index**, not a store. Its Decisions-so-far lists the decisions made; a decision lives in exactly one place - its ticket's `Answer` - so the map never restates it, only gists it. `(review-time: single-source-of-truth discipline)`

### The map body

The whole map at low resolution, loaded once per session.

```markdown
# Wayfinder: <effort name>

## Destination

<what reaching the end of this map looks like - the spec, decision, or change this effort is finding its way to. One or two lines; every session orients to it before choosing a ticket.>

## Notes

<domain; skills every session should consult; standing preferences for this effort>

## Decisions so far

<!-- the index - one line per closed ticket: enough to judge relevance -->

- **<closed ticket name>** - <one-line gist of the answer>

## Not yet specified

<!-- see "Fog of war": in-scope fog you can't ticket yet; graduates as the frontier advances -->

## Out of scope

<!-- see "Out of scope": work ruled beyond the destination; closed, never graduates -->

## Tickets

### <ticket name>

- Type: research | prototype | grilling | task
- Mode: HITL | AFK
- Blocked by: <ticket names, or "-">
- Status: open | in-progress | closed
- Question: <the decision or investigation this ticket resolves>
- Answer: <recorded on resolution>
```

### Tickets

Each ticket is an entry under `## Tickets`, sized to one ~100K-token agent session. Its `Question` is the decision it resolves. Each carries a **Type** - one of `research`, `prototype`, `grilling`, `task` (see [Ticket Types](#ticket-types)).

A session **claims** a ticket by setting its `Status: in-progress` before any work, so a concurrent session skips it. `(review-time: soft claim; matters only when the map is worked across concurrent sessions)`

**Blocking edges are plain text** in the `Blocked by` field, naming the tickets that must close first. A ticket is **unblocked** when every ticket blocking it is closed; the **frontier** is the open, unblocked, unclaimed tickets - the edge of the known. Scan the `## Tickets` section to compute the frontier; there is no tracker UI to render it. `(review-time: frontier is derived by reading the map, not queried)`

The `Answer` is recorded on resolution (see [Work through the map](#work-through-the-map)). Assets created while resolving a ticket are linked from the ticket, not pasted in.

## Ticket Types

Every ticket is either **HITL** - human in the loop, worked *with* a human who speaks for themselves - or **AFK**, driven by the agent alone. A HITL ticket only resolves through that live exchange; the agent never stands in for the human's side of it (a grilling agent that answers its own questions has broken this). `(review-time: HITL boundary; the agent must not fabricate the human's side)`

- **Research** (AFK): Reading documentation, third-party APIs, or local resources to surface a fact a decision waits on. Resolved by a `/research` subagent. Use when knowledge outside the current working directory is required.
- **Prototype** (HITL): Raise the fidelity of the discussion by making a cheap, rough, concrete artifact to react to - via the `/prototype` skill. Links the prototype as an asset. Use when "how should it look" or "how should it behave" is the key question.
- **Grilling** (HITL): Conversation via the `/grill-with-docs` skill, one question at a time. The default case.
- **Task** (HITL or AFK): Manual work that must happen before a *decision* can be made - nothing to decide, prototype, or research, but the discussion is blocked until it's done. Signing up for a service so its API can be judged, provisioning access, moving data so its shape can be seen. This is the one type that *does* rather than decides - and it earns its place by unblocking a decision, not by delivering the destination. The agent drives it alone where it can (AFK); otherwise it hands the human a precise checklist (HITL). Resolved when the work is done; the answer records what was done and any resulting facts later tickets depend on.

## Fog of war

The map is *deliberately* incomplete: don't chart what you can't yet see. Beyond the live tickets lies the **fog of war** - the dim view of decisions and investigations you can tell are coming but can't yet pin down, because they hang on questions still open. Resolving a ticket clears the fog ahead of it, graduating whatever's now specifiable into fresh tickets - one at a time, until the way to the destination is clear and no tickets remain.

The map's **Not yet specified** section is where that dim view is written down: the suspected question, the area to revisit later. Write as loosely or as fully as the view allows.

**Fog or ticket?** The test is whether you can state the question precisely now - *not* whether you can answer it now. `(review-time: fog-vs-ticket judgment; sharpness of the question, not its answerability)`

- **Ticket when** the question is already sharp - even if it's blocked and you can't act on it yet.
- **Not yet specified when** you can't yet phrase it that sharply. Don't pre-slice the fog into ticket-sized pieces.

**Not yet specified** excludes what's already decided (Decisions so far), what's already a live ticket, and what's out of scope.

## Out of scope

The destination fixes the scope, so work beyond it is **out of scope** - it isn't fog, and it doesn't belong in **Not yet specified**. It gets its own **Out of scope** section: work you've consciously ruled out of *this* effort. Scope, not sharpness, lands it here. `(review-time: scope-boundary judgment)`

Out-of-scope work never graduates - the frontier stops at the destination - so it returns only if the destination is redrawn, and then as a fresh effort.

When a ticket turns out to sit past the destination, **close it** and leave one line in the **Out of scope** section: the gist plus why it's out of scope. It stays out of **Decisions so far**, which records the route actually walked.

## Invocation

Two modes. Either way, **never resolve more than one ticket per session** - with the exception of research tickets. `(review-time: one-ticket-per-session bound keeps context within the smart zone)`

### Chart the map

User invokes with a loose idea.

1. **Name the destination.** Run a `/grill-with-docs` session to pin down what this map is finding its way to - the spec, decision, or change. The destination fixes the scope, so it's settled first.
2. **Map the frontier.** Grill again, **breadth-first** this time: fan out across the whole space rather than deep on any one thread, surfacing the open decisions and the first steps takeable now. **If this surfaces no fog** - the way to the destination is already clear, the whole journey small enough for one session - you don't need a map. Stop and ask the user how they'd like to proceed. `(review-time: no-fog exit; a well-scoped effort does not need a map)`
3. **Create the map file** at `.claude/state/wayfinder/<slug>.md`: Destination and Notes filled in, Decisions-so-far empty, the fog sketched into **Not yet specified**.
4. **Create the tickets you can specify now** under `## Tickets`, then wire `Blocked by` edges. Everything you can't yet specify stays in **Not yet specified**.
5. **Fire the research subagents.** For each `research` ticket, spin up a `/research` subagent to resolve it in parallel, capturing findings with a context pointer from the ticket.
6. Stop - charting is one session's work; it hand-resolves nothing.

### Work through the map

User invokes with a map (file path). A ticket is **optional** - without one, you pick the next frontier decision, not the user.

1. Load the **map** file - the low-res view.
2. Choose the ticket. If the user named one, use it. Otherwise take the first frontier ticket in order. **Claim it**: set `Status: in-progress` before any work.
3. Resolve it - invoke the skills the `## Notes` block names. If in doubt, use `/grill-with-docs`.
4. Record the resolution: fill the ticket's `Answer`, set `Status: closed`, and append a one-line gist to **Decisions so far**.
5. Add newly-surfaced tickets and graduate any fog the answer has made specifiable, clearing each graduated patch from **Not yet specified**. If the answer reveals a ticket sits beyond the destination, **rule it out of scope** rather than resolving it. If the decision invalidates other parts of the map, update or delete those tickets.

Concurrent sessions may work unblocked tickets in parallel (via lane mode, per `rules/parallel-agents.md`); expect the map file to be edited concurrently and re-read before writing.
