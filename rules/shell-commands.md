# Shell Commands

**When to apply:** running shell commands.

The pi gate floors wrappers to a prompt. Write the direct form.

**why-no-hook:** the model writes the command, not a file.

- Use `printenv`, not bare `env` `(review-time: see section note)`
- Prefer `VAR=value cmd` and `unset VAR; cmd` over `env` `(review-time: see section note)`
- Use the tool timeout, not `timeout` `(review-time: see section note)`
- Drop `nohup`, `time`, and `xargs`; use a loop or the find and ls tools `(review-time: see section note)`
- Run directly, not `bash -c` or `zsh -lic` `(review-time: see section note)`
- Write long bodies with Write, not heredocs. Isolated worktrees refuse heredocs and piped git `(review-time: see section note)`
- On a nonprod gcloud `ACCESS_TOKEN_EXPIRED`, run `~/.agents/scripts/gcloud-agent-login.sh nonprod` exactly once, then retry. Never refresh production; ask the user `(review-time: reacting to an error in tool output)`
