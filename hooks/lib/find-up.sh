#!/bin/bash
# Shared upward lookup for the per-edit hooks.
#
# A monorepo keeps its Biome config, and with npm or yarn workspaces its tool
# binaries, at the workspace root, above the package.json nearest the edited
# file. Biome resolves its config the same way, walking up from where it runs.

# find_up <dir> <path>...
# Prints the first <path> that exists in <dir>, then in each parent up to the
# git top level; outside a repo, only <dir> is searched. Fails when none does.
find_up() {
  local dir top path
  dir=$(cd "$1" 2>/dev/null && pwd -P) || return 1
  shift
  # git prints the top level with symlinks resolved, so dir is resolved too.
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || top="$dir"
  while :; do
    for path in "$@"; do
      if [ -e "$dir/$path" ]; then
        printf '%s\n' "$dir/$path"
        return 0
      fi
    done
    if [ "$dir" = "$top" ] || [ "$dir" = "/" ]; then
      return 1
    fi
    dir=$(dirname "$dir")
  done
}
