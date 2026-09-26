#!/bin/bash
# Tests for the per-edit hooks' scope.
#
# The em-dash autofix rewrites prose files whole, but in code touches only
# whole-line comments, so an em dash a test asserts on survives. The post-edit
# check never runs a project-wide script: that belongs to the push gate.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(cd "${TMPDIR:-/tmp}" && pwd)
TEST_ROOT=$(cd "$(mktemp -d "$TMP_ROOT/post-edit-hooks-test.XXXXXX")" && pwd)
PASSED=0
FAILED=0
EM=$'\xe2\x80\x94'

cleanup() {
  case "$TEST_ROOT" in
    "$TMP_ROOT"/post-edit-hooks-test.*) rm -rf "$TEST_ROOT" ;;
    *) echo "Refusing to clean unexpected test path: $TEST_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

pass() { PASSED=$((PASSED + 1)); echo "ok - $1"; }
fail() { FAILED=$((FAILED + 1)); echo "not ok - $1" >&2; }

run_hook() {
  printf '{"tool_input":{"file_path":"%s"}}' "$2" \
    | (cd "$TEST_ROOT" && SKIP_POST_EDIT_LINT="" SKIP_POST_EDIT_TYPECHECK="" bash "$PROJECT_DIR/hooks/$1" 2>&1)
}

echo "== em-dash autofix =="
printf 'A %s B\n' "$EM" > "$TEST_ROOT/notes.md"
run_hook post-edit-lint.sh "$TEST_ROOT/notes.md" >/dev/null
if grep -q "$EM" "$TEST_ROOT/notes.md"; then fail "a prose file is rewritten whole"; else pass "a prose file is rewritten whole"; fi

printf '/* a %s b */\nexpect(x).toBe("a %s b");\n' "$EM" "$EM" > "$TEST_ROOT/spec.ts"
run_hook post-edit-lint.sh "$TEST_ROOT/spec.ts" >/dev/null
if head -1 "$TEST_ROOT/spec.ts" | grep -q "$EM"; then fail "a comment line in code is rewritten"; else pass "a comment line in code is rewritten"; fi
if sed -n 2p "$TEST_ROOT/spec.ts" | grep -q "$EM"; then pass "a string literal in code keeps its em dash"; else fail "a string literal in code keeps its em dash"; fi

echo
echo "== post-edit check =="
PROJ="$TEST_ROOT/proj"
mkdir -p "$PROJ/src"
cat > "$PROJ/package.json" <<'JSON'
{ "name": "probe", "private": true, "scripts": { "typecheck": "exit 1", "lint:fix": "exit 1", "lint": "exit 1" } }
JSON
printf 'export const a = 1;\n' > "$PROJ/src/a.ts"
OUT=$(run_hook post-edit-typecheck.sh "$PROJ/src/a.ts"); STATUS=$?
if [ "$STATUS" -eq 0 ]; then pass "a project without biome runs no project-wide script"; else
  echo "    exit $STATUS: $OUT" >&2; fail "a project without biome runs no project-wide script"; fi

echo '{}' > "$PROJ/biome.json"
OUT=$(run_hook post-edit-typecheck.sh "$PROJ/src/a.ts"); STATUS=$?
if [ "$STATUS" -eq 0 ]; then pass "a biome project without a local biome is skipped"; else
  echo "    exit $STATUS: $OUT" >&2; fail "a biome project without a local biome is skipped"; fi

echo ""
echo "$PASSED passed; $FAILED failed"
[ "$FAILED" -eq 0 ]
