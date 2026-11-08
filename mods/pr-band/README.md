# pr-band

A Claude Code mod that draws a one-row band above the prompt with the branch's pull request. It shows the PR's state, number, title, and CI result with counts. A second row appears only for failing check names, checks waiting on approval, and flags that need you: changes requested, a merge conflict, or a branch behind main. The status line already shows the repo, branch, and PR link, so the band leaves them out. It refreshes after every turn and every 60 seconds, and toasts when CI turns green, red, or waits on an approval.

It reads `git` and `gh pr view` in the session's working directory, so `gh` must be signed in.

Every Claude Code session loads it through `CLAUDE_CODE_PLUGIN_DIRS` in `settings.json`, which names `~/.claude/mods/pr-band`. `scripts/setup-hosts.sh` links `~/.claude/mods` to this folder. An interactive session watches the folder and reloads the mod when a file changes.

Check a change with `claude plugin validate mods/pr-band` and `claude plugin test mods/pr-band`.
