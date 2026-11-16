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
# .claude/state/ is untracked and per checkout, so the gate looks in the main
# checkout first and then in the worktree.
#
# Exit 2 blocks the action and feeds the message back to the agent.
# Bypass with SKIP_EVIDENCE_GATE=1.

# shellcheck source=lib/resolve-repo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/resolve-repo.sh"
# shellcheck source=lib/state-roots.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/state-roots.sh"
# shellcheck source=lib/hook.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/hook.sh"

hook_read

case "$COMMAND" in
  *"gh pr create --help"*|*"gh pr create -h"*) exit 0 ;;
  *"gh pr create"*) ;;
  *) exit 0 ;;
esac

hook_bypass SKIP_EVIDENCE_GATE && exit 0

DIR=$(resolve_repo_dir "$COMMAND" "$CWD")
TOP=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0
BRANCH=$(git -C "$TOP" branch --show-current 2>/dev/null)
HEAD_SHA=$(git -C "$TOP" rev-parse HEAD 2>/dev/null)
[ -z "$BRANCH" ] || [ -z "$HEAD_SHA" ] && exit 0

state_roots "$TOP"
SPEC=""
for root in "${ROOTS[@]}"; do
  [ -d "$root/.claude/state/specs" ] || continue
  SPEC=$(grep -lx "branch: $BRANCH" "$root"/.claude/state/specs/*.md 2>/dev/null | head -1)
  [ -n "$SPEC" ] && break
done
[ -z "$SPEC" ] && exit 0
LEDGER=$(run_file "$BRANCH" evidence.md)

PROBLEMS=()
report() { PROBLEMS+=("  $1"); }

# Criteria checked by a test or command; manual ones are skipped. A criterion is
# a checkbox under any list marker. Its id may be wrapped in bold markers, with the
# colon inside or outside them, and may end in a lowercase letter suffix.
AC_LINE='^[-*+] \[.\] (\*\*)?AC-[0-9]+[a-z]?(\*\*)?:'
CRITERIA=$(grep -E "$AC_LINE" "$SPEC")
AC_IDS=$(printf '%s\n' "$CRITERIA" | grep -v 'verify: manual' \
  | sed -nE 's/^[-*+] \[.\] (\*\*)?(AC-[0-9]+[a-z]?)(\*\*)?:.*/\2/p')

# A checkbox in the criteria section that the pattern misses would go unchecked.
UNPARSED=$(awk '/^## /{s=($0 ~ /^## Acceptance Criteria/)} s' "$SPEC" \
  | grep -E '^[-*+] \[.\] ' | grep -vE "$AC_LINE")
while IFS= read -r line; do
  [ -n "$line" ] && report "Could not parse criterion: $line"
done <<< "$UNPARSED"

if [ -z "$CRITERIA" ] && grep -qE '^## Acceptance Criteria' "$SPEC"; then
  report "Could not parse any criteria in $(basename "$SPEC"). Write them as '- [ ] AC-1: ...'."
elif [ -z "$LEDGER" ]; then
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

if [ "${#PROBLEMS[@]}" -gt 0 ]; then
  hook_block pre-pr-evidence-gate SKIP_EVIDENCE_GATE "Refusing to open the PR for $BRANCH." \
    "${PROBLEMS[@]}" "Re-run the Spec Verifier at HEAD, fix what fails, then retry."
fi

exit 0
