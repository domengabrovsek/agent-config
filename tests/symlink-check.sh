#!/bin/bash
# Tests for hooks/symlink-check.sh. Every scenario uses a disposable HOME and
# a fake checkout; the caller's own config dir is never read.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$PROJECT_DIR/hooks/symlink-check.sh"
# Both paths are normalised: TMPDIR often carries a trailing slash, and the
# bootstrap normalises its own repo path before comparing link targets.
TMP_ROOT=$(cd "${TMPDIR:-/tmp}" && pwd)
TEST_ROOT=$(cd "$(mktemp -d "$TMP_ROOT/symlink-check-test.XXXXXX")" && pwd)
PASSED=0
FAILED=0

cleanup() {
  case "$TEST_ROOT" in
    "$TMP_ROOT"/symlink-check-test.*) rm -rf "$TEST_ROOT" ;;
    *) echo "Refusing to clean unexpected test path: $TEST_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

pass() {
  PASSED=$((PASSED + 1))
  echo "ok - $1"
}

fail() {
  FAILED=$((FAILED + 1))
  echo "not ok - $1" >&2
}

# A fake checkout carrying only what the Claude manifest links.
FAKE_REPO="$TEST_ROOT/repo"
mkdir -p "$FAKE_REPO/scripts" "$FAKE_REPO/.github"
cp "$PROJECT_DIR/scripts/setup-hosts.sh" "$FAKE_REPO/scripts/setup-hosts.sh"
for NAME in agents hooks rules skills docs references templates; do
  mkdir -p "$FAKE_REPO/$NAME"
done
: > "$FAKE_REPO/CLAUDE.md"
: > "$FAKE_REPO/settings.json"
: > "$FAKE_REPO/scripts/statusline.sh"
: > "$FAKE_REPO/.github/pull_request_template.md"

# The manifest the bootstrap creates, read from the bootstrap itself so this
# test cannot become the third copy of the list it exists to prevent.
manifest() {
  sed -n "/^CLAUDE.md|CLAUDE.md$/,/^EOF$/p" "$FAKE_REPO/scripts/setup-hosts.sh" | grep -v '^EOF$'
}

link_all() {
  local dir="$1" entry relative
  mkdir -p "$dir"
  while IFS='|' read -r entry relative; do
    [ -n "$entry" ] || continue
    ln -sfn "$FAKE_REPO/$relative" "$dir/$entry"
  done <<EOF
$(manifest)
EOF
}

run_hook() {
  AGENT_CONFIG_REPO="$FAKE_REPO" \
  CLAUDE_DOTFILES_REPO="" \
  CLAUDE_CONFIG_DIR="$1" \
  SKIP_SYMLINK_CHECK="${SKIP:-}" \
  AGENT_HOSTS_ENV="$TEST_ROOT/absent-hosts.env" \
    bash "$HOOK" 2>"$TEST_ROOT/err"
}

assert_silent() {
  local name="$1"
  run_hook "$2"
  if [ -s "$TEST_ROOT/err" ]; then
    sed -n '1,20p' "$TEST_ROOT/err" >&2
    fail "$name"
  else
    pass "$name"
  fi
}

assert_reports() {
  local name="$1" dir="$2" needle="$3"
  [ -n "$needle" ] || { fail "$name (empty needle)"; return; }
  run_hook "$dir"
  if grep -q -- "$needle" "$TEST_ROOT/err"; then pass "$name"; else
    sed -n '1,20p' "$TEST_ROOT/err" >&2
    fail "$name"
  fi
}

# A fully linked dir is silent.
CONVERGED="$TEST_ROOT/home/.claude-converged"
link_all "$CONVERGED"
assert_silent "converged dir reports nothing" "$CONVERGED"

# Every manifest entry is audited. The old hand-maintained list omitted docs,
# references and templates, so a dir missing only those looked converged.
for entry in docs references templates; do
  PARTIAL="$TEST_ROOT/home/.claude-no-$entry"
  link_all "$PARTIAL"
  rm -f "$PARTIAL/$entry"
  assert_reports "missing $entry is reported" "$PARTIAL" "/$entry MISSING"
done

# A link pointing at the wrong target is drift, not convergence.
WRONG="$TEST_ROOT/home/.claude-wrong"
link_all "$WRONG"
ln -sfn "$FAKE_REPO/rules" "$WRONG/skills"
assert_reports "wrong link target is reported" "$WRONG" "WRONG-LINK"

# A real file where a link belongs needs --adopt, so it must surface.
REAL="$TEST_ROOT/home/.claude-real"
link_all "$REAL"
rm -f "$REAL/CLAUDE.md"
echo "real file" > "$REAL/CLAUDE.md"
assert_reports "real path conflict is reported" "$REAL" "CONFLICT"

# The convergence hint names the bootstrap rather than raw ln commands.
assert_reports "drift output names the bootstrap" "$WRONG" "setup-hosts.sh --apply --host claude"

# Escape hatches stay quiet.
SKIP=1 assert_silent "SKIP_SYMLINK_CHECK=1 silences the check" "$WRONG"

MISSING_REPO="$TEST_ROOT/home/.claude-missing-repo"
link_all "$MISSING_REPO"
rm -f "$MISSING_REPO/CLAUDE.md"
AGENT_CONFIG_REPO="$TEST_ROOT/no-such-repo" CLAUDE_CONFIG_DIR="$MISSING_REPO" \
  bash "$HOOK" 2>"$TEST_ROOT/err"
if [ -s "$TEST_ROOT/err" ]; then fail "absent checkout is silent"; else pass "absent checkout is silent"; fi

ABSENT_DIR="$TEST_ROOT/home/.claude-does-not-exist"
assert_silent "absent config dir is silent" "$ABSENT_DIR"

echo ""
echo "$PASSED passed; $FAILED failed"
[ "$FAILED" -eq 0 ]
