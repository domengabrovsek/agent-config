#!/bin/bash
# Tests for hooks/herdr-pane-context.sh. A fake herdr on PATH records the
# report-metadata arguments; repos and worktrees live in a disposable dir.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$PROJECT_DIR/hooks/herdr-pane-context.sh"
TMP_ROOT=$(cd "${TMPDIR:-/tmp}" && pwd -P)
TEST_ROOT=$(cd "$(mktemp -d "$TMP_ROOT/herdr-pane-context-test.XXXXXX")" && pwd -P)
PASSED=0
FAILED=0

cleanup() {
  case "$TEST_ROOT" in
    "$TMP_ROOT"/herdr-pane-context-test.*) rm -rf "$TEST_ROOT" ;;
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
  echo "not ok - $1"
  echo "  got: $2"
}

mkdir -p "$TEST_ROOT/bin"
LOG="$TEST_ROOT/herdr.log"
cat >"$TEST_ROOT/bin/herdr" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$LOG"
EOF
chmod +x "$TEST_ROOT/bin/herdr"

REPO="$TEST_ROOT/my-repo"
git init -q -b main "$REPO"
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$REPO" worktree add -q -b feat/x "$TEST_ROOT/wt-x"
mkdir -p "$TEST_ROOT/plain"

run_hook() {
  : >"$LOG"
  printf '%s' "$2" | PATH="$TEST_ROOT/bin:$PATH" HERDR_ENV="$1" HERDR_PANE_ID=w0:p1 bash "$HOOK"
  cat "$LOG"
}

expect() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "$2"; fi
}

prefix="pane report-metadata w0:p1 --source agent-config:pane-context"

expect "skips panes outside herdr" \
  "$(run_hook 0 "{\"cwd\":\"$REPO\"}")" ""

expect "reports repo and branch, clears wt in the main checkout" \
  "$(run_hook 1 "{\"cwd\":\"$REPO\"}")" \
  "$prefix --token repo=my-repo --token branch=main --clear-token wt"

expect "reports the parent repo and worktree name in a linked worktree" \
  "$(run_hook 1 "{\"cwd\":\"$TEST_ROOT/wt-x\"}")" \
  "$prefix --token repo=my-repo --token branch=feat/x --token wt=⎇ wt-x"

expect "prefers new_cwd from CwdChanged" \
  "$(run_hook 1 "{\"cwd\":\"$REPO\",\"new_cwd\":\"$TEST_ROOT/wt-x\"}")" \
  "$prefix --token repo=my-repo --token branch=feat/x --token wt=⎇ wt-x"

expect "clears every token outside a git repo" \
  "$(run_hook 1 "{\"cwd\":\"$TEST_ROOT/plain\"}")" \
  "$prefix --clear-token repo --clear-token branch --clear-token wt"

echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
