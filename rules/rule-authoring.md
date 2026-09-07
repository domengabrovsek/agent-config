---
paths:
  - "**/rules/*.md"
  - "**/CLAUDE.md"
  - "**/agents/*.md"
  - "**/skills/**/SKILL.md"
---

# Rule Authoring Policy

**When to apply:** writing or editing any rule bullet in `rules/*.md`, `CLAUDE.md`, `agents/*.md`, or `skills/**/SKILL.md`.

## Why this exists

Rules sitting in text files are loaded into every Claude session, but loading is not enforcement. Compliance failures happen when the agent forgets or misreads. The cure isn't more rules - it's making the enforcement layer of each rule explicit so the reader (human or LLM) knows what's mechanically backed and what's attention-dependent. Where mechanical backing is possible, we add it. Where it isn't, we own that the rule depends on attention.

## The five enforcement layers

Ranked by reliability (earliest catch wins per the shift-left principle):

| Tag | Where enforced | Cost when violated |
| --- | --- | --- |
| `(hook)` | `~/.claude/hooks/*.sh` via `~/.claude/settings.json` | ~1s, fed back to Claude as a tool result |
| `(lint)` | Repo `biome.json` / `eslint.config.js` / `.markdownlint*` | `npm run check` run |
| `(CI)` | `.github/workflows/` and shared reusable workflows | PR cycle |
| `(persona)` | A `agents/*.md` persona file's guardrail section | Subagent compliance, not global |
| `(review-time: <why>)` | Human attention or Claude attention at review or response time | Open-ended |

## The marker requirement

Every **rule** bullet in an in-scope file ends with a tag. A rule bullet says "do X" or "don't Y" - the rule itself. Prose paragraphs (motivation, examples, prerequisites) carry no tag.

Format: backtick-wrapped, single space before, end of line.

Rule text itself follows the plain-language policy in `rules/communication.md` - a rule the reader has to parse twice does not get followed. `(hook)`

```markdown
- No `var` in JS/TS - use `const` or `let` `(hook)`
- Prefer interface over type for object shapes `(lint)`
- Lead with your recommendation when you have one `(review-time: subjective phrasing, not pattern-matchable)`
```

## The `(review-time)` justification

`(review-time)` is the weakest layer and the easiest place for rules to silently accumulate. To gate that:

- Every `(review-time)` tag MUST include a colon-prefixed justification: `(review-time: <one-line why>)`.
- The justification answers: *why can't a hook, linter, or CI check catch this?*
- If many bullets in a single section share the same justification, write the justification once as a `**why-no-hook:**` paragraph immediately under the section heading, then use `(review-time: see section note)` on each bullet.
- If you can't write a one-line justification, the rule can probably be checked by a hook (write it instead) or is not worth keeping.

## Multi-layer conventions

- A rule with **multiple distinct aspects** belonging to different layers gets split into separate bullets, each with its own tag.
- A rule whose **single aspect** happens to be caught at multiple layers gets the strongest tag only (hook beats lint beats CI beats persona beats review-time). No `(hook + lint)` compound tags - the strongest layer is the source of truth.

## In-scope files

- `rules/*.md`
- `CLAUDE.md`
- `agents/*.md` (only the Guardrails sections; persona prose stays untagged)
- `skills/**/SKILL.md` (only the rule bullets; procedure / steps / examples stay untagged)

Out of scope: `MEMORY.md`, `keybindings.json`, `settings.json`, `docs/`, `README.md`, generic `scripts/` files.

## Claude 5 authoring defaults

Claude 5 family models (Fable/Opus 5+) changed which instructions help and which hurt. When authoring or editing any rule, persona, or skill, apply these defaults (source: platform.claude.com prompting guide for Opus 5):

- Do not add attention-level verification instructions ("verify your work", "double-check", "re-verify before finishing") - the model self-verifies unprompted, and explicit verification instructions cause over-verification and token waste. Encode verification as mechanical gates (hooks, `/verify-done`, CI) instead. `(review-time: distinguishing attention-level nagging from concrete gate commands requires reading intent)`
- Do not add conservative-filter review instructions ("only report high-severity", "be conservative with findings") - they suppress real findings. Ask for everything and filter in a later pass. `(review-time: semantic classification of review instructions)`
- Prefer one clear directive over multi-sentence safety rails - the model is more instruction-sensitive than earlier generations; verbose rails cause over-compliance and scope distortion. When migrating older prompt text, cut rails rather than adding them. `(review-time: phrasing judgment)`

## Lifecycle - moving a rule between layers

- Adding a new rule: pick the layer at authoring time, mark it. If `(review-time)`, write the justification.
- Moving a rule up the table (adding a hook / lint config / CI check for it): change the tag and add the check in the same PR. PR description notes the layer change in one line.
- Demoting a rule (moving down): rare but valid (e.g., a hook becomes unmaintainable). PR description notes the demotion.
- Removing a rule: just delete it. No tombstone.
