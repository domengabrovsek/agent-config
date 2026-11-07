#!/bin/bash
# Auto-format files after Write/Edit tool use.
# Formats with Prettier; a Biome project is formatted by post-edit-typecheck.sh.
# Exits 0 always (non-blocking) - formatting failure should not block edits.

# shellcheck source=lib/find-up.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/find-up.sh"

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
# Both hooks run at once, so formatting here too would race its write. A
# workspace package inherits the Biome config at the monorepo root.
if find_up . biome.json biome.jsonc >/dev/null; then
  exit 0
fi

# Prettier runs only where the repo declares a config. Prettier's defaults
# would rewrite a repo with its own style, such as one formatted by standard.
# A workspace package inherits the config at the monorepo root.
PRETTIER_CONFIGS=(.prettierrc .prettierrc.json .prettierrc.json5 .prettierrc.yaml .prettierrc.yml
  .prettierrc.toml .prettierrc.js .prettierrc.mjs .prettierrc.cjs .prettierrc.ts .prettierrc.mts
  .prettierrc.cts prettier.config.js prettier.config.mjs prettier.config.cjs prettier.config.ts
  prettier.config.mts prettier.config.cts)
TOP=$(git rev-parse --show-toplevel 2>/dev/null) || TOP=.
if find_up . "${PRETTIER_CONFIGS[@]}" >/dev/null \
  || jq -e 'has("prettier")' package.json "$TOP/package.json" 2>/dev/null | grep -q true; then
  npx prettier --write "$FILE" 2>/dev/null
fi

exit 0
