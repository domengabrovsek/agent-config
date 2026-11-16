#!/bin/bash
# Shared payload reading and block output for the tool hooks.
#
# Every tool hook reads the same JSON payload and reports a block the same
# way: a `[<hook>]` prefix on the first stderr line, the bypass variable on
# the last, then exit 2. These helpers keep that shape in one place.

# hook_read
# Reads the payload from stdin into INPUT, and sets COMMAND, CWD and FILE from
# tool_input.command, cwd and tool_input.file_path with one jq call. A missing
# field or an unreadable payload leaves the variable empty. Trailing newlines
# are dropped, as a command substitution would.
# shellcheck disable=SC2034  # the sourcing hook reads whichever fields it needs
hook_read() {
  INPUT=$(cat)
  COMMAND=""
  CWD=""
  FILE=""
  {
    IFS= read -r -d '' COMMAND
    IFS= read -r -d '' CWD
    IFS= read -r -d '' FILE
  } < <(printf '%s' "$INPUT" | jq -j '
    [.tool_input.command, .cwd, .tool_input.file_path]
    | map((. // "") | tostring | gsub("\u0000"; "") | sub("\n+$"; "") + "\u0000")
    | add' 2>/dev/null)
}

# hook_bypass <var>: succeeds when the named SKIP_* variable is set to 1.
hook_bypass() {
  [ "${!1:-}" = "1" ]
}

# hook_block <name> <bypass-var> <line>...
# Prints the first line after a `[<name>]` prefix and the rest as they are,
# then the bypass hint when <bypass-var> is not empty, and exits 2.
hook_block() {
  local name="$1" bypass="$2" line
  shift 2
  echo "[$name] $1" >&2
  shift
  for line in "$@"; do echo "$line" >&2; done
  [ -n "$bypass" ] && echo "(Bypass: $bypass=1)" >&2
  exit 2
}
