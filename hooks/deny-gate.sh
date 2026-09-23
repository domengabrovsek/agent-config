#!/bin/bash
# Deny gate: enforces the settings.json deny list for every host that runs the
# hook registry. The logic lives in lib/deny-gate.ts, which shares the Pi
# permission gate's rule loader.
#
# PreToolUse hook on Bash, Write|Edit, and mcp__ tools. Exit 2 blocks the call.
# Node 22.18 or newer runs the TypeScript directly; without it the gate exits 0
# and the host's native deny rules still apply.

command -v node >/dev/null 2>&1 || exit 0
SELF=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")
exec node "$(dirname "$SELF")/lib/deny-gate.ts"
