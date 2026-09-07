---
name: sentry-issue
description: "Fetches and digests Sentry issue data (summary, tags, stack trace, breadcrumbs, latest event) by short ID, numeric issue ID, or sentry.io URL, for any Sentry org the local token can access. Use when the user mentions a Sentry issue or short ID (e.g. MY-PROJECT-4X2), pastes a sentry.io issue URL, or asks to investigate a Sentry error."
---

# Sentry Issue Investigation

Pull everything needed to debug a Sentry issue, starting from just a short ID.

## Quick start

```bash
# from this skill's own directory
scripts/sentry-issue.sh MY-PROJECT-4X2
```

Accepts a short ID (`PROJECT-ABC`), a numeric issue ID, or a full issue URL
(`https://<org>.sentry.io/issues/123456/`). Prints a compact digest:
issue summary, tags, exception chain with in-app stack frames, request info,
last 10 breadcrumbs. Full JSON payloads are saved to
`/tmp/sentry-issue-<id>.json` and `/tmp/sentry-event-<id>.json` for follow-up
`jq` queries.

## How auth and org resolution work

- **Token**: `SENTRY_AUTH_TOKEN` env -> `./.sentryclirc` -> repo-root
  `.sentryclirc` -> `~/.sentryclirc`. The token is never printed.
- **Org**: `--org <slug>` flag -> `SENTRY_ORG` env -> `.sentryclirc`
  `org` key -> auto-discovery via `GET /api/0/organizations/`. With a single
  accessible org it is used directly; with multiple orgs, short IDs are probed
  against each, while numeric IDs require `--org`.
- **Server**: `SENTRY_URL` env or `.sentryclirc` `url` key for self-hosted;
  defaults to `https://sentry.io` (which proxies org-scoped routes to the
  correct region, including EU orgs).

Required token scopes: `org:read`, `project:read`, `event:read`.

## Investigation workflow

1. Run the script with the identifier the user gave.
2. Read the digest: in-app frames (`[app]` prefix) point at the failing code;
   tags like `functionName`, `transaction`, `url`, `environment` locate the
   runtime context.
3. Open the implicated source files in the matching repo and trace the failure
   path. The Sentry project slug usually maps to a repo - check the slug
   against the repos you have locally.
4. For deeper context, query the saved JSON, e.g.:

   ```bash
   jq '.entries[] | select(.type=="exception") | .data.values[0].stacktrace.frames[] | select(.inApp) | {filename, lineNo, context}' /tmp/sentry-event-<id>.json
   jq '{stats: .stats, firstRelease: .firstRelease.version, lastRelease: .lastRelease.version}' /tmp/sentry-issue-<id>.json
   jq '.contexts' /tmp/sentry-event-<id>.json
   ```

5. For a structured root-cause investigation, continue with the `/debug`
   workflow using the gathered evidence.

## Going deeper

See [REFERENCE.md](REFERENCE.md) for the full endpoint map and payload
anatomy: other events (oldest, by ID, walking `previousEventID`/`nextEventID`),
tag value distributions, attachments, issue search, source-context jq recipes,
and what is NOT available (frame-local variables, session replay). Use it
whenever the latest-event digest is not enough evidence.

- For ad-hoc API calls beyond the script, resolve the token the same way the
  script does (inside command substitution) so it never appears in output
  `(review-time: secret handling depends on how the command is composed - not pattern-matchable by a hook)`

## Troubleshooting

- **HTTP 403**: wrong org slug or token lacks scopes - run `sentry-cli info`
  to inspect scopes (never print the token itself).
- **HTTP 404 on short ID**: short ID belongs to a different org - pass
  `--org`, or the issue was deleted.
- **`sentry-cli organizations list` JSON parse error**: known CLI 3.5.0 bug;
  the script's API-based discovery avoids it.
