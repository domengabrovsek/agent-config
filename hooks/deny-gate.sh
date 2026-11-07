#!/bin/bash
# Deny gate: enforces the settings.json deny list for every host that runs the
# hook registry. The logic lives in lib/deny-gate.ts, which shares the Pi
# permission gate's rule loader.
#
# PreToolUse hook on Bash, Write|Edit, and mcp__ tools. Exit 2 blocks the call.
# Node 22.18 or newer runs the TypeScript directly.
#
# When the gate cannot run, it blocks on Codex, which has no native deny rules,
# and passes elsewhere, where the host's native rules still apply.

NEED="Codex has no native deny rules, so tool calls stay blocked until the gate runs. Install Node.js 22.18 or newer."
if ! command -v node >/dev/null 2>&1; then
  [ "${AGENT_HOOK_HOST:-}" = codex ] || exit 0
  echo "[deny-gate] node is not on PATH. $NEED" >&2
  exit 2
fi
SELF=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")
GATE="$(dirname "$SELF")/lib/deny-gate.ts"
# The gate runs before every tool call, and reusing compiled code cuts its
# startup by about 25ms. Node keys each cache entry on a hash of the source,
# so an edited file never runs stale code.
export NODE_COMPILE_CACHE="${NODE_COMPILE_CACHE:-${TMPDIR:-/tmp}/node-compile-cache}"
[ "${AGENT_HOOK_HOST:-}" = codex ] || exec node "$GATE"
node "$GATE"
status=$?
# Exit 0 and 2 are verdicts. Anything else means node could not run the gate.
if [ "$status" -ne 0 ] && [ "$status" -ne 2 ]; then
  echo "[deny-gate] The gate exited $status. $NEED" >&2
  exit 2
fi
exit "$status"
