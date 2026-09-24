# Shell Commands

**When to apply:** running shell commands.

The pi gate floors wrappers to a prompt. Write the direct form.

**why-no-hook:** the model writes the command, not a file.

- Use `printenv`, not bare `env` `(review-time: see section note)`
- Prefer `VAR=value cmd` and `unset VAR; cmd` over `env` `(review-time: see section note)`
- Use the tool timeout, not `timeout` `(review-time: see section note)`
- Drop `nohup`, `time`, and `xargs`; use a loop or the find and ls tools `(review-time: see section note)`
- Run directly, not `bash -c` or `zsh -lic` `(review-time: see section note)`
- Write long bodies to files, not heredocs piped to `tail` `(review-time: see section note)`
