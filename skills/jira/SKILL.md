---
name: jira
description: "Read and write Jira work items through the acli CLI. Use when the user mentions a Jira ticket, issue, story, bug, or epic, drops a Jira key like SER-123, or pastes an atlassian.net/browse URL."
---

# Jira Access

Reach for `acli` (Atlassian CLI) before doing anything else.

## Detection

Use this skill when any of the following appears in the user's message:

- A Jira-style key matching `[A-Z]+-\d+` `(review-time: trigger condition for the rule, not a rule itself)`
- The words "Jira", "ticket", "issue", "story", "epic", "bug" used in a tracker sense (not a generic "there's an issue with X") `(review-time: trigger condition)`
- A Jira URL (`*.atlassian.net/browse/KEY-123`) `(review-time: trigger condition)`

If the reference is ambiguous (could be GitHub issue vs Jira), ask before assuming. `(review-time: requires judging ambiguity in the user's message)`

## Tool check

1. Run `which acli` to confirm it is installed. `(review-time: procedural step in a sequence)`
2. If installed, run `acli jira auth status` (or attempt a read command) to confirm it is authenticated. If unauthenticated, surface that to the user - do not attempt to authenticate on their behalf. `(review-time: procedural step)`
3. If not installed or not configured, tell the user and fall back to asking them for the ticket contents. `(review-time: error-handling pattern in conversation)`

## Usage

Prefer `acli` over web fetches or asking the user to paste ticket content.

Common commands:

```bash
acli jira workitem view <KEY>           # read a ticket
acli jira workitem search --jql "..."   # search
acli jira workitem comment <KEY> ...    # add comment
acli jira workitem update <KEY> ...     # update fields / transition
```

Run `acli jira workitem --help` for the current command surface - flags change between versions, so do not guess.

## Rules

- **Read first**: when a ticket is referenced, fetch it before asking the user what it says. Do not make the user paste content `acli` could have retrieved. `(review-time: ordering in conversational flow)`
- **No silent writes**: never transition, comment on, or update a ticket without explicit user confirmation. Reading is free; writing affects shared state. `(review-time: requires conversational signal of confirmation)`
- **Do not invent keys**: only act on keys the user actually provided. Do not guess project prefixes. `(review-time: requires reading user's message)`
- **Stay scoped**: fetch the specific tickets referenced, not the entire backlog. Avoid broad `--jql` sweeps unless asked. `(review-time: judging "broad" scope)`
- **Surface auth errors**: if `acli` returns an auth or permission error, report it verbatim - do not retry blindly or attempt to re-auth. `(review-time: error-handling pattern)`

## Writing tickets

- **Reporter voice**: write every ticket as someone reporting the problem before the fix and investigation are done - even when the fix already exists. Describe symptoms as currently happening, keep any proposed fix in future/conditional tense, and never reference the implementing PR or completed work in the description. PR links belong on the PR side (ticket key in PR title/description), not in the ticket body.
- **Match the project's format**: before writing, view 1-2 recent tickets the user reported in the same project and mirror their section headings and tone (e.g. "What's happening / Root cause / Why we should fix it / Proposed fix / Acceptance / Related" in plain prose).
- **Plain language**: summaries readable by non-engineers; keep deep technical detail (status codes, stack traces, code paths) out of the ticket unless the project's existing tickets carry it.
