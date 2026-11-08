# session-focus

A Claude Code mod that shows what a terminal session is working on, in a pane beside the chat. After each prompt you type, it asks Haiku for a 3 to 5 word label covering your last six prompts, such as "Fix Alerts Pane Tests". The pane opens at session start, and `/focus` opens it again.

The label survives `/clear`, because `/clear` keeps the same process and the mod keeps its prompts in session state. It skips slash commands and prompts you did not type, such as task notifications. A failed Haiku call keeps the last label and shows the failure under it.

Each prompt costs one small Haiku call, billed to the session's credentials and limited to 30 output tokens.

Every Claude Code session loads it through `CLAUDE_CODE_PLUGIN_DIRS` in `settings.json`, which names `~/.claude/mods/session-focus`. `scripts/setup-hosts.sh` links `~/.claude/mods` to this folder.

Check a change with `claude plugin validate mods/session-focus` and `claude plugin test mods/session-focus`.
