# session-focus

A Claude Code mod that shows what a terminal session is working on, in one row above the prompt. After each prompt you type, it asks Haiku for a 3 to 5 word label covering your last six prompts, such as "Fix Alerts Pane Tests". The row shows that label and the time it last changed. It stays hidden until the first label arrives.

The label survives `/clear`, because `/clear` keeps the same process and the mod keeps its prompts in session state. It skips slash commands and prompts you did not type, such as task notifications. A failed Haiku call keeps the last label and shows the failure beside it.

Inside herdr, the mod also sends the label to the agent sidebar as the `$focus` pane token, through `herdr pane report-metadata`. It sends the label when a session starts, on each prompt, and when a new label arrives, so a herdr restart or a reload of the mod never leaves the sidebar stale for more than one prompt. A session with no label yet clears the token. The herdr config in dotfiles shows that token under each agent.

Each prompt costs one small Haiku call, billed to the session's credentials and limited to 30 output tokens.

Every Claude Code session loads it through `CLAUDE_CODE_PLUGIN_DIRS` in `settings.json`, which names `~/.claude/mods/session-focus`. `scripts/setup-hosts.sh` links `~/.claude/mods` to this folder. The list names it before `pr-band`, because plugins listed earlier draw first and `pr-band` draws its band without passing on to the plugins after it. This mod draws its row and then the plugins beneath it.

Check a change with `claude plugin validate mods/session-focus` and `claude plugin test mods/session-focus`.
