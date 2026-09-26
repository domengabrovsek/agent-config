#!/bin/bash
# Auto-format files after Write/Edit tool use.
# Formats with Prettier; a Biome project is formatted by post-edit-typecheck.sh.
# Exits 0 always (non-blocking) - formatting failure should not block edits.

FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Skip if no file path or file doesn't exist
[ -z "$FILE" ] && exit 0
[ -f "$FILE" ] || exit 0

# Skip binary files
file "$FILE" 2>/dev/null | grep -q "text" || exit 0

# Skip files that formatters don't handle
case "$FILE" in
  *.png|*.jpg|*.gif|*.ico|*.woff|*.woff2|*.ttf|*.eot|*.lock) exit 0 ;;
esac

# Find project root (look for package.json)
DIR=$(dirname "$FILE")
PROJECT_ROOT=""
while [ "$DIR" != "/" ]; do
  [ -f "$DIR/package.json" ] && PROJECT_ROOT="$DIR" && break
  DIR=$(dirname "$DIR")
done

# No project root found, skip
[ -z "$PROJECT_ROOT" ] && exit 0

cd "$PROJECT_ROOT" || exit 0

# hooks/post-edit-typecheck.sh runs `biome check --write` on the same file.
# Both hooks run at once, so formatting here too would race its write.
if [ -f "biome.json" ] || [ -f "biome.jsonc" ]; then
  exit 0
fi

# Try Prettier (if configured or available)
if [ -f ".prettierrc" ] || [ -f ".prettierrc.json" ] || [ -f ".prettierrc.yml" ] || [ -f "prettier.config.js" ] || [ -f "prettier.config.mjs" ]; then
  npx prettier --write "$FILE" 2>/dev/null && exit 0
fi

# Fallback: try prettier if it's in node_modules
if [ -f "node_modules/.bin/prettier" ]; then
  npx prettier --write "$FILE" 2>/dev/null && exit 0
fi

exit 0
