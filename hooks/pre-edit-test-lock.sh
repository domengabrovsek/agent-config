#!/bin/bash
# Pre-edit test lock: only the QA Expert may edit a test file listed in the
# branch's test lock. The agent that makes a test pass never rewrites it.
#
# PreToolUse hook on Edit|Write. The lock lives at
# .claude/state/runs/<branch-slug>/tests.lock, one repo-relative path per line,
# written by the QA Expert after it commits a slice's failing tests. Without a
# lock the hook is a no-op. The hook payload carries agent_type only for
# subagents, so the main session counts as a non-QA editor.
#
# .claude/state/ is untracked and per checkout, so a worktree looks in its own
# tree first and then in the main checkout.
#
# Exit 2 blocks the edit and feeds the message back to the agent.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
AGENT=$(echo "$INPUT" | jq -r '.agent_type // empty')
[ -z "$FILE" ] && exit 0
[ "$AGENT" = "QA Expert" ] && exit 0

DIR=$(dirname "$FILE")
while [ ! -d "$DIR" ] && [ "$DIR" != "/" ]; do DIR=$(dirname "$DIR"); done
TOP=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0
BRANCH=$(git -C "$TOP" branch --show-current 2>/dev/null)
[ -z "$BRANCH" ] && exit 0

COMMON=$(git -C "$TOP" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
ROOTS=("$TOP")
[ -n "$COMMON" ] && [ "$(dirname "$COMMON")" != "$TOP" ] && ROOTS+=("$(dirname "$COMMON")")

LOCK=""
for root in "${ROOTS[@]}"; do
  candidate="$root/.claude/state/runs/${BRANCH//\//-}/tests.lock"
  [ -f "$candidate" ] && LOCK="$candidate" && break
done
[ -z "$LOCK" ] && exit 0

# Locked tests are committed, so git's own path survives symlinked prefixes.
REL=$(cd "$(dirname "$FILE")" 2>/dev/null && git ls-files --full-name -- "$(basename "$FILE")")
[ -z "$REL" ] && exit 0
if grep -qxF "$REL" "$LOCK"; then
  echo "[pre-edit-test-lock] $REL is a locked test for $BRANCH." >&2
  echo "Make the code pass the test as written. If the test itself is wrong, report it so the QA Expert fixes it." >&2
  exit 2
fi

exit 0
