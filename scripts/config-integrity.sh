#!/bin/bash
# Integrity gate for the tracked configuration files.
#
# Three checks, all cheap enough to run on every PR:
#   1. every tracked JSON file parses
#   2. no runtime-written ephemeral state reached a committed settings file
#   3. .gitattributes still declares the filter that strips it
#
# Check 2 matters because the strip filter is per-clone: `git config
# filter.strip-ephemeral-state.clean` has to be set in each checkout, and a
# clone without it commits whatever the host wrote at runtime, including the
# autoMode environment inventory (hostnames, domains, bucket and secret paths).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Keys the strip filter deletes. Keep in step with the filter command in
# README.md; this check is what catches a clone that never configured it.
EPHEMERAL_KEYS=(feedbackSurveyState lastChangelogVersion autoMode)
FILTERED_FILES=(settings.json pi/settings.json)

fail=0

note_fail() {
  echo "FAIL: $1" >&2
  fail=1
}

echo "== JSON parses =="
while IFS= read -r f; do
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
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
  blob=$(mktemp "${TMPDIR:-/tmp}/config-integrity.XXXXXX")
  git cat-file blob "HEAD:$f" > "$blob"
  found=$(python3 - "$blob" "${EPHEMERAL_KEYS[@]}" <<'PY'
import json, sys
path, keys = sys.argv[1], sys.argv[2:]
data = json.load(open(path))
print(" ".join(k for k in keys if k in data))
PY
)
  rm -f "$blob"
  if [ -n "$found" ]; then
    printf '  BAD  %s carries %s\n' "$f" "$found"
    note_fail "$f carries ephemeral key(s): $found."
    echo "      Configure the strip filter in this clone, then re-stage the file:" >&2
    echo "      git config filter.strip-ephemeral-state.clean 'jq \"del(.feedbackSurveyState, .lastChangelogVersion, .autoMode)\" 2>/dev/null || cat'" >&2
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
if [ "$fail" -eq 0 ]; then
  echo "OK: configuration is intact."
else
  echo "Configuration integrity check failed." >&2
fi
exit "$fail"
