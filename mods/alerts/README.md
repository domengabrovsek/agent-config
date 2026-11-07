# alerts

A Claude Code mod that lists unresolved Sentry issues from the last 24 hours in a pane beside the chat. Each row shows the issue's short ID as a link, its project, its occurrence and user counts, and when it was last seen. Run `/alerts` to open the pane. Press `r` or the refresh button to reload it.

It calls the `search_issues` tool of the session's `sentry` MCP server through `$.mcp.call`, which uses the engine's existing connection and credentials. The mod holds no token. The pane says when the server is not connected or the search fails. It refreshes every 5 minutes, but only in a session where `/alerts` has run, and shows the 25 most recently seen issues.

Every Claude Code session loads it through `CLAUDE_CODE_PLUGIN_DIRS` in `settings.json`, which names `~/.claude/mods/alerts`. `scripts/setup-hosts.sh` links `~/.claude/mods` to this folder.

Check a change with `claude plugin validate mods/alerts` and `claude plugin test mods/alerts`.
