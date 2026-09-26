#!/bin/bash
# Post-edit hook: biome-check the edited file, and only that file.
# Runs `biome check --write` on it when the project has a biome config and a
# local biome, so formatting and safe lint fixes land and remaining errors in
# the file block. Projects without biome get nothing here: whole-project
# typecheck and lint belong to the repo's push gate, not to every edit.
#
# Exit 2 with the report on stderr is the only code Claude Code feeds back to
# the model; any other nonzero is a silent non-blocking error, which would drop
# the very errors this hook exists to surface.
#
# Bypass: SKIP_POST_EDIT_TYPECHECK=1.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE" ] && exit 0
[ -f "$FILE" ] || exit 0
[ "$SKIP_POST_EDIT_TYPECHECK" = "1" ] && exit 0

case "$FILE" in
  */node_modules/*|*/dist/*|*/build/*) exit 0 ;;
esac

# Walk up to find the nearest package.json. A relative path would make
# `dirname` return "." forever, so anchor it before the walk.
case "$FILE" in
  /*) ;;
  *) FILE="$PWD/$FILE" ;;
esac
DIR=$(dirname "$FILE")

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

[ -f biome.json ] || [ -f biome.jsonc ] || exit 0
# A bare `npx biome` would download a biome the project never pinned.
[ -x node_modules/.bin/biome ] || exit 0

OUT=$(node_modules/.bin/biome check --write --no-errors-on-unmatched \
  --files-ignore-unknown=true "$FILE" 2>&1)
if [ $? -ne 0 ]; then
  echo "[post-edit-typecheck] biome check failed for $FILE" >&2
  echo "$OUT" | head -60 >&2
  echo "(Bypass: SKIP_POST_EDIT_TYPECHECK=1)" >&2
  exit 2
fi

exit 0
