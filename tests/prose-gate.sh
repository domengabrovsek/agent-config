#!/bin/bash
# Tests for hooks/prose-gate.sh.
#
# Two parts:
#   fixtures  strings that must block, and strings that must pass
#   corpus    every tracked markdown file must pass
#
# The corpus pass is the regression guard that matters. The block tier holds
# only words with no hits in this repo, and the corpus pass keeps that true.
# It also catches a new pattern that starts firing on writing we consider
# correct.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
GATE="$PROJECT_DIR/hooks/prose-gate.sh"
cd "$PROJECT_DIR" || exit 1

harness_init prose-gate TEST_DIR
OUT=""
STATUS=0
diagnose() { echo "    exit $STATUS, output: $OUT"; }

# run_commit <text>: prints the exit status of the gate on that commit message.
run_commit() {
  printf '%s' "$1" | python3 -c '
import json, sys
print(json.dumps({"tool_input": {"command": "git commit -m " + json.dumps(sys.stdin.read())}}))
' | "$GATE" commit >/dev/null 2>&1
  echo $?
}

# expect <status> <label> <text>...: checks the gate status on each commit message.
expect() {
  local want="$1" label="$2" t st
  shift 2
  for t in "$@"; do
    st=$(run_commit "$t")
    if [ "$st" = "$want" ]; then pass "$label: $t"; else
      echo "    got exit $st" >&2
      fail "$label: $t"
    fi
  done
}
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
expect 2 "blocks" "${MUST_BLOCK[@]}"

# Terms of art and ordinary engineering prose.
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
expect 0 "passes" "${MUST_PASS[@]}"

# Advisory words warn but never block.
echo "== advisory passes =="
ADVISORY=(
  "feat: a robust retry policy"
  "docs: a comprehensive guide"
  "refactor: leverage the shared client"
  "chore: bump deps in order to fix the audit"
  "refactor: replace the scaffolding with a real loader"
)
expect 0 "advisory passes" "${ADVISORY[@]}"

# Sentence shape is advisory and never blocks.
echo
echo "== sentence shape =="
STE_FIXTURE="$TEST_DIR/fixture.md"

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

OUT=$("$GATE" corpus "$STE_FIXTURE" 2>&1)
STATUS=$?
check "sentence shape does not block" exited 0
check "a long sentence gets an advisory" grep -q "line 3: .*-word sentence" <<< "$OUT"
check "a causal since gets an advisory" grep -q "line 5: .since the." <<< "$OUT"
check "headings, fenced code and tables are exempt from the cap" \
  not grep -qE "line (1|7|8|11): " <<< "$OUT"

# gate_status <mode> <json>: sets OUT and STATUS to the gate output and exit code on <json>.
gate_status() {
  OUT=$(printf '%s\n' "$2" | "$GATE" "$1" 2>&1)
  STATUS=$?
}

echo
echo "== plumbing =="
check "SKIP_PROSE_GATE=1 bypasses the gate" \
  [ "$(SKIP_PROSE_GATE=1 run_commit "feat: a pivotal refactor")" = 0 ]
gate_status commit '{"tool_input":{"command":"git commit --amend --no-edit"}}'
check "an amend without an edit is skipped" exited 0
gate_status commit '{"tool_input":{"command":"npm test"}}'
check "a command that is not a commit is ignored" exited 0
gate_status pr '{"tool_input":{"command":"gh pr create --title x --body \"a pivotal change\""}}'
check "pr mode blocks a pivotal body" exited 2
gate_status file '{"tool_input":{"file_path":"/nonexistent/file.md"}}'
check "a missing file exits 0" exited 0
gate_status badmode '{"tool_input":{}}'
check "an unknown mode exits 1" exited 1

# Tracked files only. Vendored markdown under node_modules is not this repo's
# prose, and scanning it turns a dependency install into a red test run.
list_corpus() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files '*.md' | sort
  else
    find . -path ./.git -prune -o -path ./node_modules -prune -o -name '*.md' -print | sort
  fi
}

echo
echo "== corpus =="
CORPUS_FAILED=0
while IFS= read -r f; do
  out=$("$GATE" corpus "$f" 2>&1)
  if [ $? -eq 2 ]; then
    echo "$out" | grep "line " | sed 's/^/      /' >&2
    fail "corpus: $f"
    CORPUS_FAILED=$((CORPUS_FAILED + 1))
  fi
done < <(list_corpus)

if [ "$CORPUS_FAILED" -eq 0 ]; then
  pass "every tracked markdown file passes the block tier"
else
  echo "  Reword them, or move the pattern to the advisory tier in prose-gate.sh." >&2
fi

finish
