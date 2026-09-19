#!/bin/bash
# Budget gate for the always-loaded rule surface: AGENTS.md plus every rule
# without paths: frontmatter. The config reached ~8,300 words one reasonable
# bullet at a time; this fails the build when it starts growing back. Raising a
# budget is a deliberate edit to this file, reviewed in the same PR as the rule
# that needs it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MAX_WORDS=3800
MAX_REVIEW_TIME=100

# Claude Code loads a rule at launch unless its frontmatter scopes it with paths:.
has_paths() {
  awk 'NR == 1 && $0 != "---" { exit 1 }
       NR > 1 && $0 == "---" { exit 1 }
       /^paths:/ { found = 1; exit }
       END { exit !found }' "$1"
}

FILES=(AGENTS.md)
for f in rules/*.md; do
  has_paths "$f" || FILES+=("$f")
done

total=0
printf '%-38s %6s\n' "file" "words"
for f in "${FILES[@]}"; do
  w=$(wc -w < "$f" | tr -d ' ')
  total=$((total + w))
  printf '%-38s %6s\n' "$f" "$w"
done
printf '%-38s %6s  (~%s tokens)\n' "TOTAL" "$total" "$((total * 4 / 3))"

review=$(grep -hoE '\(review-time' "${FILES[@]}" | wc -l | tr -d ' ')
hook=$(grep -hoE '\(hook\)' "${FILES[@]}" | wc -l | tr -d ' ')
echo
echo "review-time bullets: $review (budget $MAX_REVIEW_TIME)"
echo "hook-backed bullets: $hook"

fail=0
if [ "$total" -gt "$MAX_WORDS" ]; then
  echo "FAIL: always-loaded surface is $total words, budget is $MAX_WORDS." >&2
  echo "Cut a rule, move one behind a paths: trigger or a skill, or raise the budget here on purpose." >&2
  fail=1
fi
if [ "$review" -gt "$MAX_REVIEW_TIME" ]; then
  echo "FAIL: $review review-time bullets, budget is $MAX_REVIEW_TIME." >&2
  echo "Attention-dependent rules are the ones that get missed. Hook it, scope it, or drop it." >&2
  fail=1
fi

[ "$fail" -eq 0 ] && echo "OK: within budget."
exit "$fail"
