#!/bin/bash
# Pre-commit branch gate.
# Blocks `git commit` when HEAD is on main or master, and when the commit
# targets a directory that is not a git repo, since its branch is unknown.
# PreToolUse hook for Bash(git commit *) and Bash(git -C *). Exit 2 blocks the
# action and feeds the message back to Claude as a tool result.
# Bypass with SKIP_COMMIT_BRANCH_GATE=1 in the environment.

# shellcheck source=lib/resolve-repo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/resolve-repo.sh"
# shellcheck source=lib/once.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/once.sh"
# shellcheck source=lib/husky-hooks.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/husky-hooks.sh"
# shellcheck source=lib/hook.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/hook.sh"

hook_read
first_run_for_call "$INPUT" pre-commit-branch-gate || exit 0

case "$COMMAND" in
  *git*) ;;
  *) exit 0 ;;
esac
parse_git_command "$COMMAND" "$CWD" commit || exit 0
git_args_ask_help && exit 0

DIR=$GIT_REPO_DIR

# A new worktree's husky hooks must exist before its first commit, or git
# skips pre-commit and commit-msg for it. Runs before the bypass, which
# allows a commit to main and does not turn off the repo's own hooks.
TOP=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)
[ -n "$TOP" ] && restore_husky_hooks "$TOP" "$(git -C "$DIR" config --local --get core.hooksPath 2>/dev/null)"

hook_bypass SKIP_COMMIT_BRANCH_GATE && exit 0

if ! git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  hook_block pre-commit-branch-gate "" \
    "$DIR is not a git repo, so the commit's branch cannot be checked." \
    "Run the commit from inside the repo, or name it with git -C <repo>."
fi

# Detached HEAD prints nothing: no branch to protect.
BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)

case "$BRANCH" in
  main|master)
    hook_block pre-commit-branch-gate SKIP_COMMIT_BRANCH_GATE \
      "Refusing to commit directly to '$BRANCH'." \
      "Create a feature branch first, e.g.:" \
      "  git checkout -b <type>/<short-description>"
    ;;
esac

exit 0
