#!/bin/bash
# Tests for the pre-push gate's build env.
#
# A fresh worktree has no .env, and a build that validates its env fails
# there for reasons unrelated to the branch. The gate builds such a checkout
# with the committed .env.example, and leaves a checkout with its own env alone.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(cd "${TMPDIR:-/tmp}" && pwd)
TEST_ROOT=$(cd "$(mktemp -d "$TMP_ROOT/pre-push-gate-test.XXXXXX")" && pwd)
PASSED=0
FAILED=0

cleanup() {
  case "$TEST_ROOT" in
    "$TMP_ROOT"/pre-push-gate-test.*) rm -rf "$TEST_ROOT" ;;
    *) echo "Refusing to clean unexpected test path: $TEST_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

pass() { PASSED=$((PASSED + 1)); echo "ok - $1"; }
fail() { FAILED=$((FAILED + 1)); echo "not ok - $1" >&2; }

# The build passes only when GATE_PROBE carries the template's value.
make_project() {
  local dir="$1"
  mkdir -p "$dir/node_modules"
  git -C "$dir" init -q
  cat > "$dir/package.json" <<'JSON'
{
  "name": "probe",
  "private": true,
  "scripts": {
    "build": "node -e \"process.exit(process.env.GATE_PROBE === 'from-template' ? 0 : 1)\""
  }
}
JSON
  printf '# comment\nGATE_PROBE=from-template\n' > "$dir/.env.example"
}

run_gate() {
  local dir="$1"
  printf '{"cwd":"%s","tool_input":{"command":"git push origin feature/x"}}' "$dir" \
    | (cd "$TEST_ROOT" && CLAUDE_PROJECT_DIR="" SKIP_PUSH_GATE="" bash "$PROJECT_DIR/hooks/pre-push-gate.sh" 2>&1)
}

FRESH="$TEST_ROOT/fresh"
make_project "$FRESH"
OUT=$(run_gate "$FRESH")
case "$OUT" in
  *"build (env from .env.example) FAILED"*) echo "    got: $OUT" >&2; fail "a checkout without .env builds with the template" ;;
  *"build (env from .env.example)..."*) pass "a checkout without .env builds with the template" ;;
  *) echo "    got: $OUT" >&2; fail "a checkout without .env builds with the template" ;;
esac

LOCAL="$TEST_ROOT/local"
make_project "$LOCAL"
printf 'GATE_PROBE=local\n' > "$LOCAL/.env"
OUT=$(run_gate "$LOCAL")
case "$OUT" in
  *".env.example"*) echo "    got: $OUT" >&2; fail "a checkout with .env does not load the template" ;;
  *"build FAILED"*) pass "a checkout with .env does not load the template" ;;
  *) echo "    got: $OUT" >&2; fail "a checkout with .env does not load the template" ;;
esac

run_gate_cmd() {
  local dir="$1" cmd="$2"
  printf '{"cwd":"%s","tool_input":{"command":"%s"}}' "$dir" "$cmd" \
    | (cd "$TEST_ROOT" && CLAUDE_PROJECT_DIR="" SKIP_PUSH_GATE="" bash "$PROJECT_DIR/hooks/pre-push-gate.sh" 2>&1)
}

HOOKED="$TEST_ROOT/hooked"
make_project "$HOOKED"
mkdir -p "$HOOKED/.git/hooks"
printf '#!/bin/sh\nexit 0\n' > "$HOOKED/.git/hooks/pre-push"
chmod +x "$HOOKED/.git/hooks/pre-push"
OUT=$(run_gate_cmd "$HOOKED" "git push origin feature/x")
case "$OUT" in
  *"has its own pre-push hook"*) pass "a repo with its own pre-push hook is not gated twice" ;;
  *) echo "    got: $OUT" >&2; fail "a repo with its own pre-push hook is not gated twice" ;;
esac

OUT=$(run_gate_cmd "$HOOKED" "git push --no-verify origin feature/x")
case "$OUT" in
  *"has its own pre-push hook"*) echo "    got: $OUT" >&2; fail "--no-verify keeps the gate in force" ;;
  *"build (env from .env.example)..."*) pass "--no-verify keeps the gate in force" ;;
  *) echo "    got: $OUT" >&2; fail "--no-verify keeps the gate in force" ;;
esac

HUSKY="$TEST_ROOT/husky"
make_project "$HUSKY"
mkdir -p "$HUSKY/.husky/_"
printf '#!/bin/sh\nexit 0\n' > "$HUSKY/.husky/_/pre-push"
chmod +x "$HUSKY/.husky/_/pre-push"
git -C "$HUSKY" config core.hooksPath .husky/_
OUT=$(run_gate_cmd "$HUSKY" "git push origin feature/x")
case "$OUT" in
  *"has its own pre-push hook"*) pass "a husky hooksPath hook counts as the repo's own gate" ;;
  *) echo "    got: $OUT" >&2; fail "a husky hooksPath hook counts as the repo's own gate" ;;
esac

echo ""
echo "$PASSED passed; $FAILED failed"
[ "$FAILED" -eq 0 ]
