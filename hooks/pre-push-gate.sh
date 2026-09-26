#!/bin/bash
# Pre-push gate: block a `git push` that the repo's checks would fail.
# Runs as a PreToolUse hook on Bash(git push *) and Bash(git -C *).
#
# Order: a repo whose hooks directory is missing blocks, a repo with its own
# pre-push hook gates itself, a repo declaring `verify:fast` runs only that,
# and any other repo gets the guessed lint/typecheck/knip/test/build/audit run.
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

# Husky points the repo-local core.hooksPath at a directory `npm ci` creates. A
# checkout that never ran it has the setting but not the directory, and git
# then skips every repo hook without a word, so the push would go out ungated.
# --type=path expands a leading ~ the way git does.
HOOKS_PATH=$(git -C "$DIR" config --local --type=path --get core.hooksPath 2>/dev/null)
if [ -n "$HOOKS_PATH" ]; then
  TOP=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)
  case "$HOOKS_PATH" in
    /*) HOOKS_DIR="$HOOKS_PATH" ;;
    *) HOOKS_DIR="$TOP/$HOOKS_PATH" ;;
  esac
  if [ -n "$TOP" ] && [ ! -d "$HOOKS_DIR" ]; then
    echo "[pre-push-gate] core.hooksPath is $HOOKS_PATH, but $HOOKS_DIR does not exist, so the repo's own hooks would not run. Run 'npm ci' in $TOP, then push again." >&2
    exit 2
  fi
fi

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

# A repo with its own pre-push hook runs its own full gate on this push, so
# running ours as well repeats every check. `--no-verify` skips the repo hook,
# so ours stays in force then.
case "$COMMAND" in
  *"--no-verify"*) ;;
  *)
    REPO_HOOK=$(git -C "$PROJECT_ROOT" rev-parse --path-format=absolute --git-path hooks/pre-push 2>/dev/null)
    if [ -n "$REPO_HOOK" ] && [ -x "$REPO_HOOK" ]; then
      echo "[pre-push-gate] $PROJECT_ROOT has its own pre-push hook, which gates this push." >&2
      exit 0
    fi
    ;;
esac

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
  # A repo that declares its fast gate owns the push checks.
  if has_script "verify:fast"; then
    run_step "verify:fast" "npm run verify:fast"
    echo "[pre-push-gate] verify:fast passed." >&2
    exit 0
  fi
  has_script lint && run_step "lint" "CI=true npm run lint --silent"
  has_script typecheck && run_step "typecheck" "CI=true npm run typecheck --silent"
  has_script knip && run_step "knip" "CI=true npm run knip --silent"
  has_script test && run_step "test" "CI=true npm test --silent"
  # A checkout with no local env, such as a fresh worktree, builds with the
  # committed template. CI builds with throwaway values the same way. The
  # template stays scoped to the build: test runners read env too.
  if [ ! -f .env ] && [ ! -f .env.local ] && [ -f .env.example ]; then
    has_script build && run_step "build (env from .env.example)" \
      "set -a && . ./.env.example && set +a && CI=true npm run build --silent"
  else
    has_script build && run_step "build" "CI=true npm run build --silent"
  fi
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
