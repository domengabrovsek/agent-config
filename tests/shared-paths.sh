#!/bin/bash
# Every ~/.agents path named in shared content must resolve to a real file in
# this checkout, and its first segment must be a tree the bootstrap links.
#
# This is the guard for the class of bug where a shared file names a path that
# does not exist: the rulebook skill shipped 14 such rows after a vendoring,
# and nothing caught it. Repo-only, so it holds in CI and on any machine.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$PROJECT_DIR" || exit 1
PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); echo "ok - $1"; }
fail() { FAILED=$((FAILED + 1)); echo "not ok - $1" >&2; }

# The shared manifest, read from the bootstrap so this test cannot drift from
# what --apply actually creates.
manifest() {
  awk '/manage_link "shared\/\$NAME"/,/^EOF$/' scripts/setup-hosts.sh \
    | grep -E '^[A-Za-z0-9_.-]+\|'
}

repo_path_for() {
  local segment="$1" entry relative
  while IFS='|' read -r entry relative; do
    [ "$entry" = "$segment" ] && { printf '%s\n' "$relative"; return 0; }
  done <<EOF
$(manifest)
EOF
  return 1
}

echo "== shared manifest =="
MANIFEST_COUNT=$(manifest | wc -l | tr -d ' ')
if [ "$MANIFEST_COUNT" -gt 0 ]; then
  pass "bootstrap declares $MANIFEST_COUNT shared entries"
else
  fail "could not read the shared manifest from scripts/setup-hosts.sh"
  echo ""
  echo "$PASSED passed; $FAILED failed"
  exit 1
fi

echo
echo "== ~/.agents references resolve =="
# shellcheck disable=SC2088  # the tilde is literal text being searched for
REFS=$(grep -rhoE '~/\.agents/[A-Za-z0-9._/-]+' skills/ rules/ agents/ 2>/dev/null \
  | sed 's/[.,]$//' | sort -u)

if [ -z "$REFS" ]; then
  fail "no ~/.agents references found; the grep or the layout changed"
else
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    rest="${ref#\~/.agents/}"
    segment="${rest%%/*}"
    remainder=""
    case "$rest" in
      */*) remainder="${rest#*/}" ;;
    esac

    if ! relative=$(repo_path_for "$segment"); then
      fail "$ref names '$segment', which the bootstrap does not link"
      continue
    fi

    target="$relative"
    [ -n "$remainder" ] && target="$relative/$remainder"
    target="${target%/}"

    if [ -e "$target" ]; then
      pass "$ref -> $target"
    else
      fail "$ref -> $target (missing in this checkout)"
    fi
  done <<EOF
$REFS
EOF
fi

echo
echo "== no host-specific paths outside Claude-only mechanisms =="
# Hooks and settings.json really are Claude-only, so those rows may name
# ~/.claude. Anything else in shared content should use the shared root.
# shellcheck disable=SC2088  # the tilde is literal text being searched for
STRAY=$(grep -rnE '~/\.claude/' skills/ rules/ agents/ 2>/dev/null \
  | grep -vE '~/\.claude/(hooks|settings\.json|rules)' || true)
if [ -z "$STRAY" ]; then
  pass "shared content names no stray ~/.claude paths"
else
  fail "shared content still names host-specific paths:"
  printf '%s\n' "$STRAY" >&2
fi

echo ""
echo "$PASSED passed; $FAILED failed"
[ "$FAILED" -eq 0 ]
