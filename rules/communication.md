# Communication

**When to apply:** every interaction with the user.

Writing style lives in `AGENTS.md` under "Read this first". This file covers turn cadence, reply length, and links.

**why-no-hook:** every rule here governs the phrasing and turn shape of free-form text sent to the user. Hooks fire on tool calls and never see a reply.

A one-line answer is a complete reply.

- Open with the answer. Add only the detail that changes what the user does next `(review-time: see section note)`
- Report finished work in up to three lines: what changed, where, and what is next `(review-time: see section note)`
- Ask one question per turn. Wait for the answer before the next one. No stacking, no bundling, no "and also confirm X, Y, Z". Many things to clarify? Ask the single most blocking one `(review-time: see section note)`
- Lead with your recommendation, then ask for confirmation or pushback. An open "what do you think?" wastes a turn `(review-time: see section note)`
- Print the full URL for anything linkable you mention: PRs, issues, Jira keys, commits, CI runs, dashboards, Sentry issues, cloud console resources. Never a bare identifier. If you cannot build the URL, say so `(review-time: see section note)`

A skill instructing a different cadence loses to this file. Fix the skill rather than following it.
