#!/bin/bash
# Shared repo resolution for the PreToolUse git hooks.
#
# A hook runs with its own cwd, which is not the directory the tool call ran
# in, so the repo has to be recovered from the payload and the command text.
# Three hooks need the same answer; a copy each is how they drifted apart in
# the first place, with one of them ignoring the payload cwd entirely.
#
# Precedence, most explicit first:
#   1. `git -C <path>` in the command
#   2. a leading `cd <path> &&` prefix, which moves the repo away from the
#      recorded cwd (that cwd is the shell's directory before the cd runs)
#   3. the tool call's cwd, since a worktree runs from the worktree while
#      CLAUDE_PROJECT_DIR stays on the main checkout
#   4. CLAUDE_PROJECT_DIR, then the hook's own cwd

# resolve_repo_dir <command> <payload-cwd> [subcommand]
# Prints an absolute directory. Never fails: a garbled parse yields a path
# that simply does not resolve, and every caller already handles that.
resolve_repo_dir() {
  local command="$1"
  local cwd="$2"
  local subcommand="${3:-[a-z][a-z-]*}"
  local c_path cd_path dir

  c_path=$(printf '%s\n' "$command" \
    | sed -n "s/.*git -C  *\([^ ]*\)  *${subcommand}.*/\1/p" | head -1)

  cd_path=""
  case "$command" in
    "cd "*)
      cd_path=${command#cd }
      cd_path=${cd_path%%"&&"*}
      cd_path=${cd_path%%";"*}
      cd_path=$(printf '%s\n' "$cd_path" \
        | sed "s/^[[:space:]]*//;s/[[:space:]]*\$//;s/^[\"']//;s/[\"']\$//")
      ;;
  esac

  dir="${c_path:-${cd_path:-${cwd:-${CLAUDE_PROJECT_DIR:-$PWD}}}}"

  # A -C or cd path is relative to the tool call's cwd, not the hook's.
  case "$dir" in
    /*) ;;
    *) dir="${cwd:-$PWD}/$dir" ;;
  esac

  printf '%s\n' "$dir"
}
