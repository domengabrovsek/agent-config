#!/bin/bash
# Shared helpers for the shell suites. Source it, call harness_init when the
# suite needs a temp dir, and end with finish. Bash 3.2 compatible for macOS.

PASSED=0
FAILED=0

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

# harness_init [-P] <name> [var]: makes a temp dir in <var> (default TEST_ROOT)
# and removes it on exit. -P resolves symlinks for suites comparing git paths.
harness_init() {
  local pwd_flag=-L
  [ "$1" = -P ] && { pwd_flag=-P; shift; }
  HARNESS_PREFIX="$(cd "${TMPDIR:-/tmp}" && pwd $pwd_flag)/$1-test."
  HARNESS_DIR=$(cd "$(mktemp -d "${HARNESS_PREFIX}XXXXXX")" && pwd $pwd_flag)
  printf -v "${2:-TEST_ROOT}" '%s' "$HARNESS_DIR"
  trap harness_cleanup EXIT HUP INT TERM
}

harness_cleanup() {
  case "$HARNESS_DIR" in
    "$HARNESS_PREFIX"*) rm -rf "$HARNESS_DIR" ;;
    *) echo "Refusing to clean unexpected test path: $HARNESS_DIR" >&2 ;;
  esac
}

pass() { PASSED=$((PASSED + 1)); echo "ok - $1"; }
fail() { FAILED=$((FAILED + 1)); echo "not ok - $1" >&2; }

finish() {
  printf '\n%s passed; %s failed\n' "$PASSED" "$FAILED"
  [ "$FAILED" -eq 0 ] || exit 1
  exit 0
}

# check <name> <command...>: passes when the command succeeds. A suite may
# define diagnose to print its own context on a failure.
check() {
  local name="$1"
  shift
  if "$@"; then pass "$name"; else
    echo "    failed: $*" >&2
    if declare -F diagnose >/dev/null; then diagnose >&2; fi
    fail "$name"
  fi
}

not() { ! "$@"; }

# Predicates on the OUT and STATUS a suite's runner sets. Each runs any
# arguments left after its own, so `exited 2 says "x"` checks both.
exited() { [ "${STATUS:-}" -eq "$1" ] || return 1; shift; [ $# -eq 0 ] || "$@"; }
says() { case "$OUT" in *"$1"*) ;; *) return 1 ;; esac; shift; [ $# -eq 0 ] || "$@"; }
omits() { case "$OUT" in *"$1"*) return 1 ;; esac; shift; [ $# -eq 0 ] || "$@"; }

# payload <command> [cwd]: a PreToolUse payload for a Bash call.
payload() {
  if [ $# -ge 2 ]; then
    jq -nc --arg c "$1" --arg d "$2" '{tool_input: {command: $c}, cwd: $d}'
  else
    jq -nc --arg c "$1" '{tool_input: {command: $c}}'
  fi
}

# make_repo <dir>: a repo on main whose first commit holds whatever <dir> has.
make_repo() {
  mkdir -p "$1"
  git -C "$1" init -q -b main
  git -C "$1" add -A
  git -C "$1" commit -q --allow-empty -m "chore: init"
}

# stub <dir> <name>: an executable <dir>/<name> whose body is read from stdin.
stub() {
  mkdir -p "$1"
  cat > "$1/$2"
  chmod +x "$1/$2"
}
