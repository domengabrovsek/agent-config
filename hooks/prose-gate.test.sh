#!/bin/bash
# Tests for hooks/prose-gate.sh.
#
# Two parts:
#   fixtures  strings that must block, and strings that must pass
#   corpus    every tracked markdown file must pass
#
# The corpus pass is the regression guard that matters. The tier split was
# chosen because these words had zero hits in this repo; the corpus pass is
# what keeps that true, and what catches a new pattern that starts firing on
# writing we consider correct.
#
# Usage: bash hooks/prose-gate.test.sh

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/hooks/prose-gate.sh"
cd "$ROOT"

PASSED=0
FAILED=0

fail() {
  echo "  FAIL: $1" >&2
  FAILED=$((FAILED + 1))
}

ok() {
  PASSED=$((PASSED + 1))
}

# run_commit <text> -> exit status of the gate on that commit message
run_commit() {
  printf '%s' "$1" | python3 -c '
import json, sys
print(json.dumps({"tool_input": {"command": "git commit -m " + json.dumps(sys.stdin.read())}}))
' | "$GATE" commit >/dev/null 2>&1
  echo $?
}

# ---------------------------------------------------------------------------
# Must block
# ---------------------------------------------------------------------------
echo "== must block =="
MUST_BLOCK=(
  "feat: a pivotal refactor"
  "feat: this will facilitate the rollout"
  "fix: numerous edge cases"
  "docs: showcase the new flow"
  "docs: a testament to the design"
  "feat: crucial change to the loader"
  "refactor: the intricate interplay of modules"
  "feat: utilize the shared client"
  "feat: a seamless migration"
  "refactor: delve into the parser"
  "docs: the enduring landscape of vibrant tapestry"
  "feat: it serves as the entry point"
  "feat: the module boasts three exports"
  "refactor: move the substrate to a new nexus"
  "docs: the bedrock of the endgame"
  "docs: our north star for the flywheel"
  "chore: in the event that the build fails"
  "chore: skipped due to the fact that CI was red"
  "docs: it is important to run the gate first"
  "docs: it's worth noting the ordering constraint"
  "fix: done. Let me know if you need anything else"
  "fix: I hope this helps"
  "docs: Great question, here is the answer"
  "fix: this could potentially break the loader"
  "docs: a holistic paradigm with real synergy"
  "refactor: extract the salient orthogonal parts"
)

for t in "${MUST_BLOCK[@]}"; do
  st=$(run_commit "$t")
  if [ "$st" = "2" ]; then ok; else fail "expected block, got exit $st: $t"; fi
done

# ---------------------------------------------------------------------------
# Must pass - terms of art and ordinary engineering prose
# ---------------------------------------------------------------------------
echo "== must pass =="
MUST_PASS=(
  "feat(hooks): add the prose gate"
  "refactor(rules): cut the always-loaded rule surface"
  "feat: reduce the attack surface of the upload path"
  "feat: add three features behind a flag"
  "fix: the feature flag defaulted to on"
  "fix: normalise the vector before comparing"
  "test: add a harness for the retry path"
  "docs: describe the injection surface"
  "fix: guard against a null pointer in the parser"
  "perf: cut p99 from 840ms to 120ms"
  "refactor: move the loader into its own module"
  "chore: pin the node version to 22.11.0"
  "fix: the compiler validates queries at build time"
  "docs: record why the ordering constraint exists"
)

for t in "${MUST_PASS[@]}"; do
  st=$(run_commit "$t")
  if [ "$st" = "0" ]; then ok; else fail "expected pass, got exit $st: $t"; fi
done

# ---------------------------------------------------------------------------
# Advisory words warn but never block
# ---------------------------------------------------------------------------
echo "== advisory passes =="
ADVISORY=(
  "feat: a robust retry policy"
  "docs: a comprehensive guide"
  "refactor: leverage the shared client"
  "chore: bump deps in order to fix the audit"
  "refactor: replace the scaffolding with a real loader"
)

for t in "${ADVISORY[@]}"; do
  st=$(run_commit "$t")
  if [ "$st" = "0" ]; then ok; else fail "advisory must not block, got exit $st: $t"; fi
done

# ---------------------------------------------------------------------------
# Sentence shape - advisory, never blocks
# ---------------------------------------------------------------------------
echo "== sentence shape =="
STE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/prose-gate-ste.XXXXXX")
STE_FIXTURE="$STE_DIR/fixture.md"

cat > "$STE_FIXTURE" <<'STE'
# A heading long enough to trip the cap if headings were ever counted at all by the check

The post-edit lint hook reads the added lines from the diff and then walks every check in turn before it decides whether to block the write or only warn.

We skipped the retry since the queue was already drained.

```
this fenced line is long enough to trip the cap if fenced code were ever counted by the sentence check at all
```

| a column header long enough to trip the cap if tables were counted | b |
| --- | --- |

Short line. This one passes.
STE

STE_OUT=$("$GATE" corpus "$STE_FIXTURE" 2>&1)
STE_STATUS=$?
rm -rf "$STE_DIR"

if [ "$STE_STATUS" = "0" ]; then ok; else fail "sentence shape must not block, got exit $STE_STATUS"; fi

if echo "$STE_OUT" | grep -q "line 3: .*-word sentence"; then ok; else fail "expected a long-sentence advisory on line 3"; fi

if echo "$STE_OUT" | grep -q "line 5: .since the."; then ok; else fail "expected a causal \"since\" advisory on line 5"; fi

if echo "$STE_OUT" | grep -qE "line (1|7|8|11): "; then
  fail "headings, fenced code and tables must be exempt from the cap"
else
  ok
fi

# ---------------------------------------------------------------------------
# Bypass and mode plumbing
# ---------------------------------------------------------------------------
echo "== plumbing =="
st=$(SKIP_PROSE_GATE=1 bash -c 'printf "%s" "$0" | python3 -c "
import json, sys
print(json.dumps({\"tool_input\": {\"command\": \"git commit -m \" + json.dumps(sys.stdin.read())}}))
" | '"$GATE"' commit >/dev/null 2>&1; echo $?' "feat: a pivotal refactor")
if [ "$st" = "0" ]; then ok; else fail "SKIP_PROSE_GATE=1 should bypass, got exit $st"; fi

echo '{"tool_input":{"command":"git commit --amend --no-edit"}}' | "$GATE" commit >/dev/null 2>&1
if [ $? = 0 ]; then ok; else fail "amend/no-edit should be skipped"; fi

echo '{"tool_input":{"command":"npm test"}}' | "$GATE" commit >/dev/null 2>&1
if [ $? = 0 ]; then ok; else fail "non-commit command should be ignored"; fi

echo '{"tool_input":{"command":"gh pr create --title x --body \"a pivotal change\""}}' | "$GATE" pr >/dev/null 2>&1
if [ $? = 2 ]; then ok; else fail "pr mode should block a pivotal body"; fi

echo '{"tool_input":{"file_path":"/nonexistent/file.md"}}' | "$GATE" file >/dev/null 2>&1
if [ $? = 0 ]; then ok; else fail "missing file should exit 0"; fi

echo '{"tool_input":{}}' | "$GATE" badmode >/dev/null 2>&1
if [ $? = 1 ]; then ok; else fail "unknown mode should exit 1"; fi

# ---------------------------------------------------------------------------
# Corpus - every tracked markdown file must pass
# ---------------------------------------------------------------------------
# Tracked files only. Vendored markdown under node_modules is not this repo's
# prose, and scanning it turns a dependency install into a red test run.
list_corpus() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files '*.md' | sort
  else
    find . -path ./.git -prune -o -path ./node_modules -prune -o -name '*.md' -print | sort
  fi
}

echo "== corpus =="
CORPUS_FAILED=0
while IFS= read -r f; do
  out=$("$GATE" corpus "$f" 2>&1)
  if [ $? -eq 2 ]; then
    echo "  FAIL: $f" >&2
    echo "$out" | grep "line " | sed 's/^/      /' >&2
    CORPUS_FAILED=$((CORPUS_FAILED + 1))
  fi
done < <(list_corpus)

if [ "$CORPUS_FAILED" -eq 0 ]; then
  ok
else
  FAILED=$((FAILED + CORPUS_FAILED))
  echo "  $CORPUS_FAILED markdown file(s) trip the block tier." >&2
  echo "  Reword them, or move the pattern to the advisory tier in prose-gate.sh." >&2
fi

# ---------------------------------------------------------------------------
echo
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ] || exit 1
echo "OK"
