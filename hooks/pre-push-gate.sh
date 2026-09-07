#!/bin/bash
# Pre-push gate: block `git push` if lint/typecheck/knip/test/build/audit fail.
# Runs as a PreToolUse hook on Bash(git push *) and Bash(git -C *).
# Exit code 2 blocks the action and sends the error message to Claude.
# Bypass with SKIP_PUSH_GATE=1, in the environment or inline in the command.

# shellcheck source=lib/resolve-repo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/resolve-repo.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only gate on `git push` (and not `git push --help`, etc.)
case "$COMMAND" in
  *"git push --help"*|*"git push -h"*) exit 0 ;;
  *"git push"*|*"git -C "*) ;;
  *) exit 0 ;;
esac

# Honor escape hatch. PreToolUse hooks inherit the Claude Code process env,
# not the tool command's, so an inline SKIP_PUSH_GATE=1 prefix is only
# visible in the command string.
case "$COMMAND" in
  *"SKIP_PUSH_GATE=1"*)
    echo "SKIP_PUSH_GATE=1 - bypassing pre-push gate." >&2
    exit 0 ;;
esac
if [ "$SKIP_PUSH_GATE" = "1" ]; then
  echo "SKIP_PUSH_GATE=1 - bypassing pre-push gate." >&2
  exit 0
fi

# `git -C <path> push` never contains the literal "git push", so a command
# without either is not ours to gate.
case "$COMMAND" in
  *"git push"*) ;;
  *) printf '%s\n' "$COMMAND" | grep -q 'git -C  *[^ ]*  *push' || exit 0 ;;
esac

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
DIR=$(resolve_repo_dir "$COMMAND" "$CWD" push)

# Find project root: walk up looking for package.json or *.tf
PROJECT_ROOT=""
PROJECT_TYPE=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  if [ -f "$DIR/package.json" ]; then
    PROJECT_ROOT="$DIR"
    PROJECT_TYPE="node"
    break
  fi
  if ls "$DIR"/*.tf >/dev/null 2>&1; then
    PROJECT_ROOT="$DIR"
    PROJECT_TYPE="terraform"
    break
  fi
  DIR=$(dirname "$DIR")
done

# No matching project - skip silently (Claude config repo, dotfiles, docs-only)
[ -z "$PROJECT_ROOT" ] && exit 0

cd "$PROJECT_ROOT" || exit 0

run_step() {
  local label="$1"
  local cmd="$2"
  echo "[pre-push-gate] $label..." >&2
  OUT=$(bash -c "$cmd" 2>&1)
  STATUS=$?
  if [ $STATUS -ne 0 ]; then
    echo "[pre-push-gate] $label FAILED. Fix before pushing (or set SKIP_PUSH_GATE=1 to bypass):" >&2
    echo "$OUT" | tail -40 >&2
    exit 2
  fi
}

if [ "$PROJECT_TYPE" = "node" ]; then
  # A fresh worktree has no node_modules; the checks below would fail with
  # noise unrelated to the branch. Fail with the actionable step instead.
  if [ ! -d "$PROJECT_ROOT/node_modules" ]; then
    echo "[pre-push-gate] $PROJECT_ROOT has no node_modules - run 'npm ci' there first (or bypass with SKIP_PUSH_GATE=1)." >&2
    exit 2
  fi
  has_script() {
    node -e "const p=require('./package.json'); process.exit(p.scripts?.['$1'] ? 0 : 1)" 2>/dev/null
  }
  has_script lint && run_step "lint" "CI=true npm run lint --silent"
  has_script typecheck && run_step "typecheck" "CI=true npm run typecheck --silent"
  has_script knip && run_step "knip" "CI=true npm run knip --silent"
  has_script test && run_step "test" "CI=true npm test --silent"
  has_script build && run_step "build" "CI=true npm run build --silent"
  # Only critical advisories block: pre-existing high/moderate transitive CVEs are
  # Dependabot's job, not a push gate's, and would otherwise block unrelated work.
  command -v npm >/dev/null 2>&1 && run_step "audit" "npm audit --audit-level=critical"
fi

if [ "$PROJECT_TYPE" = "terraform" ]; then
  command -v terraform >/dev/null 2>&1 || exit 0
  run_step "terraform fmt" "terraform fmt -check -recursive"
  run_step "terraform validate" "terraform validate"
fi

echo "[pre-push-gate] All checks passed." >&2
exit 0
