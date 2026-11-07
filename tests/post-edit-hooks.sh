#!/bin/bash
# Tests for the per-edit hooks' scope.
#
# The em-dash autofix rewrites prose files whole, but in code touches only
# whole-line comments, so an em dash a test asserts on survives. The post-edit
# check never runs a project-wide script: that belongs to the push gate.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
harness_init post-edit-hooks
EM=$'\xe2\x80\x94'
STUB_LOG="$TEST_ROOT/stub.log"
export STUB_LOG

# run_hook <hook> <file>: sets OUT and STATUS, and starts STUB_LOG empty.
run_hook() {
  : > "$STUB_LOG"
  OUT=$(printf '{"tool_input":{"file_path":"%s"}}' "$2" \
    | (cd "$TEST_ROOT" && SKIP_POST_EDIT_LINT="" SKIP_POST_EDIT_TYPECHECK="" bash "$PROJECT_DIR/hooks/$1" 2>&1))
  STATUS=$?
}
diagnose() { echo "    exit $STATUS: $OUT"; echo "    calls: $(cat "$STUB_LOG")"; }
em_on_line() { sed -n "$1p" "$2" | grep -q "$EM"; }
logged() { grep -qxF -- "$1" "$STUB_LOG"; }

echo "== em-dash autofix =="
printf 'A %s B\n' "$EM" > "$TEST_ROOT/notes.md"
run_hook post-edit-lint.sh "$TEST_ROOT/notes.md"
check "a prose file is rewritten whole" not grep -q "$EM" "$TEST_ROOT/notes.md"

printf '/* a %s b */\nexpect(x).toBe("a %s b");\n' "$EM" "$EM" > "$TEST_ROOT/spec.ts"
run_hook post-edit-lint.sh "$TEST_ROOT/spec.ts"
check "a comment line in code is rewritten" not em_on_line 1 "$TEST_ROOT/spec.ts"
check "a string literal in code keeps its em dash" em_on_line 2 "$TEST_ROOT/spec.ts"

echo
echo "== post-edit check =="
PROJ="$TEST_ROOT/proj"
mkdir -p "$PROJ/src"
cat > "$PROJ/package.json" <<'JSON'
{ "name": "probe", "private": true, "scripts": { "typecheck": "exit 1", "lint:fix": "exit 1", "lint": "exit 1" } }
JSON
printf 'export const a = 1;\n' > "$PROJ/src/a.ts"
run_hook post-edit-typecheck.sh "$PROJ/src/a.ts"
check "a project without biome runs no project-wide script" exited 0

echo '{}' > "$PROJ/biome.json"
run_hook post-edit-typecheck.sh "$PROJ/src/a.ts"
check "a biome project without a local biome is skipped" exited 0

echo
echo "== monorepo biome config =="

# A workspace keeps the Biome config and binary at its root, while a package
# that lists prettier has its own prettier. The stubs log every call.
BIN="$TEST_ROOT/bin"
stub "$BIN" npx <<'STUB'
#!/bin/bash
echo "npx $*" >> "$STUB_LOG"
STUB

MONO="$TEST_ROOT/mono"
PKG="$MONO/packages/app"
mkdir -p "$PKG/src" "$PKG/node_modules/.bin"
git -C "$MONO" init -q
echo '{}' > "$MONO/biome.json"
echo '{ "name": "mono", "private": true }' > "$MONO/package.json"
echo '{ "name": "app", "private": true }' > "$PKG/package.json"
stub "$MONO/node_modules/.bin" biome <<'STUB'
#!/bin/bash
echo "biome $*" >> "$STUB_LOG"
STUB
: > "$PKG/node_modules/.bin/prettier"
printf 'export const a = 1;\n' > "$PKG/src/a.ts"

PATH="$BIN:$PATH" run_hook auto-format.sh "$PKG/src/a.ts"
check "a package under a root biome config skips prettier" not grep -q prettier "$STUB_LOG"

# A relative file path gives a relative project root, and the hook has already
# cd'd into it by the time it looks for the config.
PATH="$BIN:$PATH" run_hook auto-format.sh "mono/packages/app/src/a.ts"
check "a relative path under a root biome config skips prettier" not grep -q prettier "$STUB_LOG"

run_hook post-edit-typecheck.sh "$PKG/src/a.ts"
check "a package under a root biome config is checked with the root's biome" \
  logged "biome check --write --no-errors-on-unmatched --files-ignore-unknown=true $PKG/src/a.ts"

# A config above the git top level belongs to some other project.
OUTSIDE="$TEST_ROOT/outside"
INNER="$OUTSIDE/repo"
mkdir -p "$INNER/src" "$INNER/node_modules/.bin"
git -C "$INNER" init -q
echo '{}' > "$OUTSIDE/biome.json"
echo '{ "name": "inner", "private": true }' > "$INNER/package.json"
cp "$MONO/node_modules/.bin/biome" "$INNER/node_modules/.bin/biome"
printf 'export const b = 2;\n' > "$INNER/src/b.ts"
run_hook post-edit-typecheck.sh "$INNER/src/b.ts"
check "a biome config above the repo is ignored" not test -s "$STUB_LOG"

echo
echo "== prettier config =="

# An installed prettier alone does not opt a repo into Prettier's defaults.
STYLED="$TEST_ROOT/styled"
mkdir -p "$STYLED/src" "$STYLED/node_modules/.bin"
echo '{ "name": "styled", "private": true }' > "$STYLED/package.json"
: > "$STYLED/node_modules/.bin/prettier"
printf 'export const c = 3;\n' > "$STYLED/src/c.ts"
PATH="$BIN:$PATH" run_hook auto-format.sh "$STYLED/src/c.ts"
check "a repo without a prettier config is not formatted" not test -s "$STUB_LOG"

echo '{ "name": "styled", "private": true, "prettier": {} }' > "$STYLED/package.json"
PATH="$BIN:$PATH" run_hook auto-format.sh "$STYLED/src/c.ts"
check "a prettier key in package.json formats the file" logged "npx prettier --write $STYLED/src/c.ts"

echo '{ "name": "styled", "private": true }' > "$STYLED/package.json"
echo '{}' > "$STYLED/.prettierrc.cjs"
PATH="$BIN:$PATH" run_hook auto-format.sh "$STYLED/src/c.ts"
check "a .prettierrc.cjs config formats the file" logged "npx prettier --write $STYLED/src/c.ts"

# A workspace package inherits the Prettier config at the monorepo root.
PMONO="$TEST_ROOT/pmono"
PPKG="$PMONO/packages/app"
mkdir -p "$PPKG/src"
git -C "$PMONO" init -q
echo '{ "name": "pmono", "private": true }' > "$PMONO/package.json"
echo '{}' > "$PMONO/.prettierrc"
echo '{ "name": "app", "private": true }' > "$PPKG/package.json"
printf 'export const d = 4;\n' > "$PPKG/src/d.ts"
PATH="$BIN:$PATH" run_hook auto-format.sh "$PPKG/src/d.ts"
check "a workspace package uses the root prettier config" logged "npx prettier --write $PPKG/src/d.ts"

rm "$PMONO/.prettierrc"
echo '{ "name": "pmono", "private": true, "prettier": {} }' > "$PMONO/package.json"
PATH="$BIN:$PATH" run_hook auto-format.sh "$PPKG/src/d.ts"
check "a workspace package uses the root package.json prettier key" logged "npx prettier --write $PPKG/src/d.ts"

finish
