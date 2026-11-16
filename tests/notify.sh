#!/bin/bash
# Tests for scripts/notify.sh against a stub osascript, so no real
# notification is shown.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
SCRIPT="$PROJECT_DIR/scripts/notify.sh"
harness_init notify
OUT=""
STATUS=0

BIN="$TEST_ROOT/bin"
LOG="$TEST_ROOT/calls.log"

# The stub answers the frontmost-app query with STUB_FRONT and logs every
# other call one argument per line.
stub "$BIN" osascript <<'EOF'
#!/bin/bash
case "$*" in
  *"System Events"*) printf '%s\n' "$STUB_FRONT"; exit 0 ;;
esac
printf '%s\n' "$@" >> "$STUB_LOG"
EOF

# run <frontmost-app> [arg...]: sets OUT and STATUS for the harness predicates.
# shellcheck disable=SC2034
run() {
  : > "$LOG"
  OUT=$(PATH="$BIN:$PATH" STUB_LOG="$LOG" STUB_FRONT="$1" bash "$SCRIPT" "${@:2}" 2>&1)
  STATUS=$?
}

logged() { grep -qxF -- "$1" "$LOG"; }
nothing_logged() { [ ! -s "$LOG" ]; }

run "Safari" 'say "hi" \ there'
check "a quoted message succeeds" exited 0
check "the message reaches AppleScript as an argument" logged 'say "hi" \ there'
check "the script text carries no message" logged 'display notification (item 1 of argv) with title "Agent" sound name "default"'

run "Safari"
check "the default message is sent" logged "Agent needs your input"

run "Ghostty" "hello"
check "a frontmost terminal skips the notification" exited 0 nothing_logged

run "Code" "hello"
check "a frontmost IDE skips the notification" nothing_logged

run "Safari" --help
check "--help prints the usage" exited 0 says "Usage: ~/.agents/scripts/notify.sh"
check "--help sends nothing" nothing_logged

finish
