---
name: reverse-engineer
description: "Reverse-engineers how a product, site, app, or library you like works, and writes a clean-room behavior spec from the evidence. Use when the user says 'reverse engineer', 'how does <product> do <feature>', or wants to rebuild something they have seen."
---

# Reverse Engineer

Explain how this works: $ARGUMENTS

The output is a **clean-room spec**: what the target does, proven by evidence, with none of its code. A rebuild written from the spec is the user's own work.

## Steps

1. **Route the target.** Name its kind and pick the cheapest reader that shows behavior. Put every clone or extract in a `mktemp -d` directory outside the project. The step is done when the kind and reader are stated:

   | Kind | Reader |
   | --- | --- |
   | Open-source repo or library | Clone it into the temp directory, read the source and its tests |
   | Website or web app | A browser tool (Claude in Chrome, Playwright MCP) for page text, network requests, and the shipped JS. Without one, fetch the page and its JS bundles directly |
   | Electron app | `npx @electron/asar extract <path>/app.asar <tmpdir>` (macOS: `<App>.app/Contents/Resources`), then read the JS |
   | CLI tool | `--help`, man pages, run it on sample inputs, its config files |
   | Public API | Its docs, then real requests and responses |
   | Native binary or mobile app | Stop and tell the user this skill reads source, bundles, and observed behavior only |

2. **Map before reading code.** Find the entry points, the routes or commands, and the endpoints and strings that name features. Rank modules by how many places reference them, and read down that list. Done when the map names where the feature most likely lives.
3. **Trace one feature end to end**, from the user action to the stored or returned result. Done when every hop in the path has a cited claim.
4. **Write the spec** to `.claude/state/research/YYYY-MM-DD-reverse-<short-slug>.md` with these sections: Summary, Architecture, Data model, Behavior (each feature as a testable requirement), Interfaces and formats, Evidence, Unknowns. Done when Unknowns lists everything still unproven.
5. **Hand off the rebuild.** This session has read the target, so a rebuild starts in a new session. Run `/handoff` with the spec path, where `/spec` and `/plan` take over. Offer a parity harness that runs the same inputs through the original and the rebuild and reports the match rate.

## Evidence

Tag every claim:

- **Observed**: seen directly. Cite the file and line, URL and request, or command and output `(review-time: requires judging each claim against its source)`
- **Inferred**: reasoned from observations. Name the observations it rests on `(review-time: requires judging each claim against its source)`
- **Unknown**: not yet proven. Say what would prove it `(review-time: requires judging each claim against its source)`

## Clean room

- Inspect only targets the user owns, licenses, or can openly access, within their terms `(review-time: ownership and terms need human context)`
- The spec states behavior in your own words: no copied code, minified identifiers, or asset files `(review-time: requires reading the spec against the source)`
- Leave license checks, DRM, and paywalls intact. Record them as Unknowns `(review-time: requires recognizing protection mechanisms)`
- A rebuild runs in a fresh context that reads only the spec, never the target `(review-time: context separation is a session choice)`
