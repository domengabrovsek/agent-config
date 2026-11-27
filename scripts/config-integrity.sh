#!/bin/bash
# Integrity gate for the tracked configuration files.
#
# Four checks, all cheap enough to run on every PR:
#   1. every tracked JSON file parses
#   2. no runtime-written ephemeral state reached a committed settings file
#   3. .gitattributes still declares the filter that strips it
#   4. a configured strip filter matches the current one
#
# Check 2 matters because the strip filter is per-clone: `git config
# filter.strip-ephemeral-state.clean` has to be set in each checkout, and a
# clone without it commits whatever the host wrote at runtime, including the
# autoMode environment inventory (hostnames, domains, bucket and secret paths).
set -euo pipefail

case "${1:-}" in
  -h|--help) sed -n '2,/^[^#]/s/^# \{0,1\}//p' "$0"; exit 0 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Dotted key paths the strip filter deletes. Keep in step with the filter
# command in README.md; this check is what catches a clone that never
# configured it. Hand-written autoMode rules outside environment are tracked.
EPHEMERAL_KEYS=(feedbackSurveyState lastChangelogVersion autoMode.environment)
STRIP_FILTER='jq "del(.feedbackSurveyState, .lastChangelogVersion, .autoMode.environment) | if .autoMode == {} then del(.autoMode) else . end" 2>/dev/null || cat'
FILTERED_FILES=(settings.json pi/settings.json)

fail=0

note_fail() {
  echo "FAIL: $1" >&2
  fail=1
}

echo "== JSON parses =="
while IFS= read -r f; do
  # Slurp so an empty file or several concatenated values fail: one document is required.
  if jq -es 'length == 1' "$f" >/dev/null 2>&1; then
    printf '  ok   %s\n' "$f"
  else
    printf '  BAD  %s\n' "$f"
    note_fail "$f is not valid JSON."
  fi
done < <(git ls-files '*.json')

echo
echo "== no ephemeral state committed =="
# Read the stored blob, not the working file. In a clone that has the filter
# configured, the working file legitimately carries runtime state that the
# filter strips on the way into the index; only what reached a commit is a
# leak. Without the filter the two are identical, which is the case CI runs.
for f in "${FILTERED_FILES[@]}"; do
  git cat-file -e "HEAD:$f" 2>/dev/null || continue
  found=$(git cat-file blob "HEAD:$f" |
    jq -r '[$ARGS.positional[] as $k | select(getpath($k | split(".")) != null) | $k] | join(" ")' --args "${EPHEMERAL_KEYS[@]}")
  if [ -n "$found" ]; then
    printf '  BAD  %s carries %s\n' "$f" "$found"
    note_fail "$f carries ephemeral key(s): $found."
    echo "      Configure the strip filter in this clone, then re-stage the file:" >&2
    echo "      git config filter.strip-ephemeral-state.clean '$STRIP_FILTER'" >&2
    echo "      git config filter.strip-ephemeral-state.smudge cat" >&2
  else
    printf '  ok   %s\n' "$f"
  fi
done

echo
echo "== strip filter still declared =="
for f in "${FILTERED_FILES[@]}"; do
  if grep -qE "^${f//\//\\/}[[:space:]].*filter=strip-ephemeral-state" .gitattributes; then
    printf '  ok   %s\n' "$f"
  else
    printf '  BAD  %s\n' "$f"
    note_fail "$f lost its filter=strip-ephemeral-state declaration in .gitattributes."
  fi
done

echo
echo "== configured strip filter is current =="
# A stale filter silently strips tracked keys on commit, so a clone that set
# one must match. CI configures none and skips this.
configured=$(git config --get filter.strip-ephemeral-state.clean || true)
if [ -z "$configured" ]; then
  echo "  skip none configured"
elif [ "$configured" = "$STRIP_FILTER" ]; then
  echo "  ok   filter.strip-ephemeral-state.clean"
else
  echo "  BAD  filter.strip-ephemeral-state.clean"
  note_fail "this clone's strip filter is stale."
  echo "      git config filter.strip-ephemeral-state.clean '$STRIP_FILTER'" >&2
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "OK: configuration is intact."
else
  echo "Configuration integrity check failed." >&2
fi
exit "$fail"
