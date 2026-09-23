#!/bin/bash
# Pre-PR evidence gate: blocks opening a PR while a spec's acceptance criteria
# lack passing evidence recorded at the current commit.
#
# PreToolUse hook on Bash(gh pr create *). The gate applies only when a spec in
# .claude/state/specs/ declares `branch: <current branch>` in its frontmatter;
# without one it is a no-op. The evidence ledger lives at
# .claude/state/runs/<branch-slug>/evidence.md and is written by the Spec
# Verifier. A criterion whose check is `manual` never blocks: the PR body lists
# it for the user instead.
#
# .claude/state/ is untracked and per checkout, so a worktree looks in its own
# tree first and then in the main checkout.
#
# Exit 2 blocks the action and feeds the message back to the agent.
# Bypass with SKIP_EVIDENCE_GATE=1.

# shellcheck source=lib/resolve-repo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/resolve-repo.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

case "$COMMAND" in
  *"gh pr create --help"*|*"gh pr create -h"*) exit 0 ;;
  *"gh pr create"*) ;;
  *) exit 0 ;;
esac

[ "$SKIP_EVIDENCE_GATE" = "1" ] && exit 0

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
DIR=$(resolve_repo_dir "$COMMAND" "$CWD")
TOP=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0
BRANCH=$(git -C "$TOP" branch --show-current 2>/dev/null)
HEAD_SHA=$(git -C "$TOP" rev-parse HEAD 2>/dev/null)
[ -z "$BRANCH" ] || [ -z "$HEAD_SHA" ] && exit 0

COMMON=$(git -C "$TOP" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
ROOTS=("$TOP")
[ -n "$COMMON" ] && [ "$(dirname "$COMMON")" != "$TOP" ] && ROOTS+=("$(dirname "$COMMON")")

SPEC=""
for root in "${ROOTS[@]}"; do
  [ -d "$root/.claude/state/specs" ] || continue
  SPEC=$(grep -lx "branch: $BRANCH" "$root"/.claude/state/specs/*.md 2>/dev/null | head -1)
  [ -n "$SPEC" ] && break
done
[ -z "$SPEC" ] && exit 0

LEDGER=""
for root in "${ROOTS[@]}"; do
  candidate="$root/.claude/state/runs/${BRANCH//\//-}/evidence.md"
  [ -f "$candidate" ] && LEDGER="$candidate" && break
done

FAILED=0
report() {
  [ "$FAILED" -eq 0 ] && echo "[pre-pr-evidence-gate] Refusing to open the PR for $BRANCH." >&2
  FAILED=1
  echo "  $1" >&2
}

# Criteria checked by a test or command; manual ones are skipped.
AC_IDS=$(grep -E '^- \[.\] AC-[0-9]+:' "$SPEC" | grep -v 'verify: manual' \
  | sed -E 's/^- \[.\] (AC-[0-9]+):.*/\1/')

if [ -z "$LEDGER" ]; then
  report "No evidence ledger for spec $(basename "$SPEC"). Run the Spec Verifier."
else
  for ac in $AC_IDS; do
    row=$(grep -E "^\| *$ac *\|" "$LEDGER" | tail -1)
    if [ -z "$row" ]; then
      report "$ac has no ledger row."
      continue
    fi
    status=$(printf '%s' "$row" | awk -F'|' '{gsub(/ /,"",$3); print $3}')
    sha=$(printf '%s' "$row" | awk -F'|' '{gsub(/[ `]/,"",$6); print $6}')
    if [ "$status" != "PASS" ]; then
      report "$ac is $status, not PASS."
    elif [ "${#sha}" -lt 7 ] || [ "${HEAD_SHA#"$sha"}" = "$HEAD_SHA" ]; then
      report "$ac was verified at ${sha:-no commit}, not HEAD ${HEAD_SHA:0:7}."
    fi
  done
fi

if [ "$FAILED" -eq 1 ]; then
  echo "Re-run the Spec Verifier at HEAD, fix what fails, then retry." >&2
  echo "(Bypass: SKIP_EVIDENCE_GATE=1)" >&2
  exit 2
fi

exit 0
