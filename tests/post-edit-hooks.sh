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

echo
echo "== monorepo biome config =="

# A workspace keeps the Biome config and binary at its root, while a package
# that lists prettier has its own prettier. The stubs log every call.
STUB_LOG="$TEST_ROOT/stub.log"
export STUB_LOG
BIN="$TEST_ROOT/bin"
mkdir -p "$BIN"
cat > "$BIN/npx" <<'STUB'
#!/bin/bash
echo "npx $*" >> "$STUB_LOG"
STUB
chmod +x "$BIN/npx"

MONO="$TEST_ROOT/mono"
PKG="$MONO/packages/app"
mkdir -p "$MONO/node_modules/.bin" "$PKG/src" "$PKG/node_modules/.bin"
git -C "$MONO" init -q
echo '{}' > "$MONO/biome.json"
echo '{ "name": "mono", "private": true }' > "$MONO/package.json"
echo '{ "name": "app", "private": true }' > "$PKG/package.json"
cat > "$MONO/node_modules/.bin/biome" <<'STUB'
#!/bin/bash
echo "biome $*" >> "$STUB_LOG"
STUB
chmod +x "$MONO/node_modules/.bin/biome"
: > "$PKG/node_modules/.bin/prettier"
printf 'export const a = 1;\n' > "$PKG/src/a.ts"

: > "$STUB_LOG"
PATH="$BIN:$PATH" run_hook auto-format.sh "$PKG/src/a.ts" >/dev/null
if grep -q prettier "$STUB_LOG"; then
  echo "    calls: $(cat "$STUB_LOG")" >&2; fail "a package under a root biome config skips prettier"
else pass "a package under a root biome config skips prettier"; fi

: > "$STUB_LOG"
run_hook post-edit-typecheck.sh "$PKG/src/a.ts" >/dev/null
if grep -qxF -- "biome check --write --no-errors-on-unmatched --files-ignore-unknown=true $PKG/src/a.ts" "$STUB_LOG"; then
  pass "a package under a root biome config is checked with the root's biome"
else echo "    calls: $(cat "$STUB_LOG")" >&2; fail "a package under a root biome config is checked with the root's biome"; fi

# A config above the git top level belongs to some other project.
OUTSIDE="$TEST_ROOT/outside"
INNER="$OUTSIDE/repo"
mkdir -p "$INNER/src" "$INNER/node_modules/.bin"
git -C "$INNER" init -q
echo '{}' > "$OUTSIDE/biome.json"
echo '{ "name": "inner", "private": true }' > "$INNER/package.json"
cp "$MONO/node_modules/.bin/biome" "$INNER/node_modules/.bin/biome"
printf 'export const b = 2;\n' > "$INNER/src/b.ts"
: > "$STUB_LOG"
run_hook post-edit-typecheck.sh "$INNER/src/b.ts" >/dev/null
if [ -s "$STUB_LOG" ]; then
  echo "    calls: $(cat "$STUB_LOG")" >&2; fail "a biome config above the repo is ignored"
else pass "a biome config above the repo is ignored"; fi

echo ""
echo "$PASSED passed; $FAILED failed"
[ "$FAILED" -eq 0 ]
