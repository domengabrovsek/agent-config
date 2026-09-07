#!/bin/bash
# Post-edit lint hook backing rules/comments.md, rules/typescript.md,
# rules/database.md and rules/infrastructure.md: code-structure checks on
# newly added lines, plus a whole-file em-dash autofix.
#
# Prose checks (word lists, scaffolding phrases) live in hooks/prose-gate.sh,
# which also covers commit messages and PR bodies.
#
# Bypass: SKIP_POST_EDIT_LINT=1.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# No file path or file vanished - bail.
[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# Escape hatch.
[ "$SKIP_POST_EDIT_LINT" = "1" ] && exit 0

# Skip noisy / generated / vendored files.
case "$FILE" in
  *package-lock.json|*yarn.lock|*pnpm-lock.yaml) exit 0 ;;
  *.min.js|*.min.css|*.map|*.bundle.js) exit 0 ;;
  */node_modules/*|*/.git/*|*/dist/*|*/build/*) exit 0 ;;
esac

# --- 1. Em-dash auto-fix (whole file, idempotent, silent) ---
if LC_ALL=C grep -q $'\xe2\x80\x94' "$FILE" 2>/dev/null; then
  sed -i '' $'s/\xe2\x80\x94/-/g' "$FILE"
fi

# --- Skip docs/text: prose comment markers cause false positives ---
case "$FILE" in
  *.md|*.markdown|*.txt|*.rst|*.adoc|*.tex) exit 0 ;;
esac

FILE_DIR=$(dirname "$FILE")
if ! git -C "$FILE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# Untracked file: treat whole file as added.
if git -C "$FILE_DIR" ls-files --error-unmatch "$FILE" >/dev/null 2>&1; then
  ADDED=$(git -C "$FILE_DIR" diff --unified=0 HEAD -- "$FILE" 2>/dev/null | grep -E '^\+[^+]' | sed 's/^\+//')
else
  ADDED=$(cat "$FILE")
fi

[ -z "$ADDED" ] && exit 0

VIOLATIONS=""

# --- 2. Ticket / PR / JIRA / ADR refs inside comments ---
TICKETS=$(echo "$ADDED" | grep -nE \
  '(//|#|/\*|^\s*\*).*(\b[A-Z]{2,}-[0-9]+\b|[[:space:]]#[0-9]+\b|\b[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+\b|\b[Aa][Dd][Rr][[:space:]-]+[0-9]+\b|\b(Fixes|Closes|Refs|Resolves)[[:space:]]+(#|[A-Z]{2,}-))' \
  2>/dev/null || true)

if [ -n "$TICKETS" ]; then
  VIOLATIONS+="Ticket / PR / JIRA / ADR reference detected in newly added comment(s). Remove the ref - those belong in PR descriptions, ADR files, and git blame, not in code:
$TICKETS

"
fi

# --- 3. Consecutive // comment lines in JS/TS (rules/comments.md: multi-line must use /* */) ---
case "$FILE" in
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs)
    CONSEC_SLASH=$(echo "$ADDED" | awk '
      /^[[:space:]]*\/\// { if (prev) print NR": "$0; prev=1; next }
      { prev=0 }
    ' 2>/dev/null || true)
    if [ -n "$CONSEC_SLASH" ]; then
      VIOLATIONS+="Consecutive // comment lines. rules/comments.md: multi-line comments must use /* */, never a stack of //:
$CONSEC_SLASH

"
    fi
    ;;
esac

# --- 4. Consecutive -- SQL comment lines (rules/comments.md: multi-line must use /* */) ---
case "$FILE" in
  *.sql)
    CONSEC_DASH=$(echo "$ADDED" | awk '
      /^[[:space:]]*--/ { if (prev) print NR": "$0; prev=1; next }
      { prev=0 }
    ' 2>/dev/null || true)
    if [ -n "$CONSEC_DASH" ]; then
      VIOLATIONS+="Consecutive -- SQL comment lines. rules/comments.md: multi-line comments must use /* */, never a stack of --:
$CONSEC_DASH

"
    fi
    ;;
esac

# --- 5. Tracker refs inside Terraform description = "..." attributes ---
case "$FILE" in
  *.tf|*.tfvars)
    TF_DESC_REFS=$(echo "$ADDED" | grep -nE \
      'description[[:space:]]*=.*(\b[A-Z]{2,}-[0-9]+\b|[[:space:]]#[0-9]+\b|\b[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+\b|\b[Aa][Dd][Rr][[:space:]-]+[0-9]+\b|\b(Fixes|Closes|Refs|Resolves)[[:space:]]+(#|[A-Z]{2,}-))' \
      2>/dev/null || true)
    if [ -n "$TF_DESC_REFS" ]; then
      VIOLATIONS+="Tracker reference inside Terraform description attribute. rules/comments.md: descriptions surface in terraform-docs and module-consumer docs - tracker refs belong in PR descriptions, ADR files, and git blame:
$TF_DESC_REFS

"
    fi
    ;;
esac

# --- 6. New `var` declarations in JS/TS (rules/typescript.md: never use var) ---
case "$FILE" in
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs)
    VAR_DECL=$(echo "$ADDED" | grep -nE '^[[:space:]]*var[[:space:]]+[A-Za-z_$]' 2>/dev/null || true)
    if [ -n "$VAR_DECL" ]; then
      VIOLATIONS+="New \`var\` declaration. rules/typescript.md: use \`const\` (or \`let\` when reassignment is required); never \`var\`:
$VAR_DECL

"
    fi
    ;;
esac

# --- 7. New TODO/FIXME/XXX/HACK markers in code (engineering-principles: complete code only) ---
TODOS=$(echo "$ADDED" | grep -nE '\b(TODO|FIXME|XXX|HACK)\b' 2>/dev/null || true)
if [ -n "$TODOS" ]; then
  VIOLATIONS+="TODO / FIXME / XXX / HACK marker. rules/engineering-principles.md: complete code only - no placeholders. Either finish the work now or open a tracked issue and remove the marker:
$TODOS

"
fi

# --- 8. SELECT * in SQL files (rules/database.md: explicitly list columns) ---
case "$FILE" in
  *.sql)
    SELECT_STAR=$(echo "$ADDED" | grep -niE '\bselect[[:space:]]+\*' 2>/dev/null || true)
    if [ -n "$SELECT_STAR" ]; then
      VIOLATIONS+="\`SELECT *\` detected. rules/database.md: list columns explicitly. Catalog the columns you actually need:
$SELECT_STAR

"
    fi
    ;;
esac

# --- 9. `:latest` Docker tag in Dockerfile / compose / k8s (rules/infrastructure.md) ---
case "$FILE" in
  *Dockerfile*|*docker-compose*.y*ml|*compose.y*ml|*/k8s/*.y*ml)
    LATEST_TAG=$(echo "$ADDED" | grep -nE '^[[:space:]]*(FROM[[:space:]]+[^:[:space:]]+:latest\b|image:[[:space:]]*[^:[:space:]]+:latest\b)' 2>/dev/null || true)
    if [ -n "$LATEST_TAG" ]; then
      VIOLATIONS+="\`:latest\` Docker tag detected. rules/infrastructure.md: pin a specific version so the build is reproducible:
$LATEST_TAG

"
    fi
    ;;
esac

if [ -n "$VIOLATIONS" ]; then
  echo "[post-edit-lint] $FILE" >&2
  echo "$VIOLATIONS" >&2
  exit 2
fi

exit 0
