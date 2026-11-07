#!/bin/bash
# Shared package.json lookups for the edit, PR, push and verify hooks.

# package_root <dir>
# Prints the nearest directory at or above <dir> that holds a package.json,
# stopping below /. Unlike find_up it crosses the git top level, because an
# edited project may sit outside any repo. Fails when none does.
package_root() {
  local dir="$1"
  # A relative path would make dirname return "." forever.
  case "$dir" in
    /*) ;;
    *) dir="$PWD/$dir" ;;
  esac
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    if [ -f "$dir/package.json" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

# has_script <name>
# Succeeds when ./package.json declares a non-empty script <name>.
has_script() {
  jq -e --arg s "$1" '(.scripts[$s] // "") != ""' package.json >/dev/null 2>&1
}
