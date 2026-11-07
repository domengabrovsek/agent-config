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

INPUT=$(cat)
first_run_for_call "$INPUT" pre-commit-branch-gate || exit 0
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

case "$COMMAND" in
  *git*) ;;
  *) exit 0 ;;
esac
parse_git_command "$COMMAND" "$CWD" commit || exit 0
git_args_ask_help && exit 0

[ "$SKIP_COMMIT_BRANCH_GATE" = "1" ] && exit 0

DIR=$GIT_REPO_DIR
if ! git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  echo "[pre-commit-branch-gate] $DIR is not a git repo, so the commit's branch cannot be checked." >&2
  echo "Run the commit from inside the repo, or name it with git -C <repo>." >&2
  exit 2
fi

# Detached HEAD prints nothing: no branch to protect.
BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)

case "$BRANCH" in
  main|master)
    echo "[pre-commit-branch-gate] Refusing to commit directly to '$BRANCH'." >&2
    echo "Create a feature branch first, e.g.:" >&2
    echo "  git checkout -b <type>/<short-description>" >&2
    echo "(Bypass: SKIP_COMMIT_BRANCH_GATE=1)" >&2
    exit 2
    ;;
esac

exit 0
