#!/bin/bash
# Post-edit hook: run typecheck and lint for .ts/.tsx files.
# Uses npm scripts if available, falls back to a locally installed tsc.
#
# Exit 2 with the report on stderr is the only code Claude Code feeds back to
# the model; any other nonzero is a silent non-blocking error, which would drop
# the very type errors this hook exists to surface.
#
# Bypass: SKIP_POST_EDIT_TYPECHECK=1.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only process .ts and .tsx files
case "$FILE" in
  *.ts|*.tsx) ;;
  *) exit 0 ;;
esac

[ "$SKIP_POST_EDIT_TYPECHECK" = "1" ] && exit 0

case "$FILE" in
  */node_modules/*|*/dist/*|*/build/*) exit 0 ;;
esac

# Walk up to find the nearest package.json. A relative path would make
# `dirname` return "." forever, so anchor it before the walk.
DIR=$(dirname "$FILE")
case "$DIR" in
  /*) ;;
  *) DIR="$PWD/$DIR" ;;
esac

PROJECT_ROOT=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  if [ -f "$DIR/package.json" ]; then
    PROJECT_ROOT="$DIR"
    break
  fi
  DIR=$(dirname "$DIR")
done

[ -z "$PROJECT_ROOT" ] && exit 0
cd "$PROJECT_ROOT" || exit 0

has_script() {
  node -e "const p=require('./package.json'); process.exit(p.scripts?.['$1'] ? 0 : 1)" 2>/dev/null
}

REPORT=""

# Typecheck: prefer the npm script. Fall back to tsc only when the project is
# actually a TypeScript project (a tsconfig) and tsc is already installed;
# bare `npx tsc` would download the compiler to typecheck a project that never
# asked for one.
if has_script typecheck; then
  OUT=$(npm run typecheck --silent 2>&1) || REPORT="$REPORT
typecheck failed:
$OUT"
elif [ -f "tsconfig.json" ] && [ -x "node_modules/.bin/tsc" ]; then
  OUT=$(node_modules/.bin/tsc --noEmit 2>&1) || REPORT="$REPORT
typecheck failed:
$OUT"
fi

# Lint: prefer lint:fix, fall back to lint.
if has_script "lint:fix"; then
  OUT=$(npm run lint:fix --silent 2>&1) || REPORT="$REPORT
lint failed:
$OUT"
elif has_script lint; then
  OUT=$(npm run lint --silent 2>&1) || REPORT="$REPORT
lint failed:
$OUT"
fi

if [ -n "$REPORT" ]; then
  echo "[post-edit-typecheck] $FILE" >&2
  echo "$REPORT" | tail -40 >&2
  echo "(Bypass: SKIP_POST_EDIT_TYPECHECK=1)" >&2
  exit 2
fi

exit 0
