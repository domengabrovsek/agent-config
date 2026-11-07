# pr-fleet

A Claude Code mod that lists your open pull requests across every repo in a pane beside the chat. Each row shows the CI result, the review decision, the count of unresolved review threads, the merge state, and a link to the PR. Run `/fleet` to open the pane. Press `r` or the refresh button to reload it.

It runs one `gh api graphql` search for `is:pr is:open author:@me`, so `gh` must be installed and signed in. The pane says which of the two is missing. One search costs one GitHub GraphQL rate-limit point. The mod refreshes every 60 seconds, but only in a session where `/fleet` has run, and shows the first 50 PRs.

Every Claude Code session loads it through `CLAUDE_CODE_PLUGIN_DIRS` in `settings.json`, which names `~/.claude/mods/pr-fleet`. `scripts/setup-hosts.sh` links `~/.claude/mods` to this folder.

Check a change with `claude plugin validate mods/pr-fleet` and `claude plugin test mods/pr-fleet`.
