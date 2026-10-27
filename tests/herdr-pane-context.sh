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
  kill "${SERVER_PID:-}" 2>/dev/null
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
case "\$1 \$2" in
  "workspace get") printf '{"result":{"workspace":{"label":"%s"}}}\n' "\${FAKE_SPACE:-space-a}" ;;
  *)
    tokens=\$(printf '%s\n' "\$@" | grep -c -- '-token\$')
    [ "\$tokens" -le 16 ] || exit 1
    printf '%s\n' "\$*" >>"$LOG" ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/herdr"
SOCKET="$TEST_ROOT/herdr.sock"
VIEW_LOG="$TEST_ROOT/view.log"
python3 - "$SOCKET" "$VIEW_LOG" <<'PY_SERVER' &
import json, socket, sys
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
    server.bind(sys.argv[1])
    server.listen()
    while True:
        conn, _ = server.accept()
        with conn:
            request = json.loads(conn.recv(4096))
            with open(sys.argv[2], "a") as log:
                log.write(f"{request['method']} {request['params']['sort'][1]['field']['token']}\n")
            conn.sendall(b'{"result":{}}\n')
PY_SERVER
SERVER_PID=$!
for _ in $(seq 50); do
  [ -S "$SOCKET" ] || ! kill -0 "$SERVER_PID" 2>/dev/null && break
  sleep 0.1
done
if [ ! -S "$SOCKET" ]; then
  echo "Bail out! The fake herdr socket server did not start at $SOCKET" >&2
  exit 1
fi

REPO="$TEST_ROOT/my-repo"
git init -q -b main "$REPO"
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$REPO" worktree add -q -b feat/x "$TEST_ROOT/wt-x"
mkdir -p "$TEST_ROOT/plain"
git init -q -b main "$TEST_ROOT/plain2"
git clone -q --bare "$REPO" "$TEST_ROOT/bare-repo.git"
git -C "$TEST_ROOT/bare-repo.git" worktree add -q "$TEST_ROOT/bare-wt" main
SUPER="$TEST_ROOT/super"
git init -q -b main "$SUPER"
git -C "$SUPER" -c protocol.file.allow=always submodule add -q "$REPO" sub-repo

run_hook() {
  : >"$LOG"
  printf '%s' "$2" | PATH="$TEST_ROOT/bin:$PATH" HERDR_ENV="$1" HERDR_PANE_ID=w0:p1 \
    HERDR_SOCKET_PATH="$SOCKET" XDG_STATE_HOME="$TEST_ROOT/state" bash "$HOOK"
  sed -E 's/ --clear-token c[0-9]+//g' "$LOG"
}

expect() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "$2"; fi
}

prefix="pane report-metadata w0:p1 --source agent-config:pane-context"

expect "skips panes outside herdr" \
  "$(run_hook 0 "{\"cwd\":\"$REPO\"}")" ""

expect "reports repo and branch, clears wt in the main checkout" \
  "$(run_hook 1 "{\"cwd\":\"$REPO\"}")" \
  "$prefix --token repo=my-repo --token branch=main --clear-token wt"$'\n'"$prefix --clear-token icon --token c0=●"

expect "reports the parent repo and worktree name in a linked worktree" \
  "$(run_hook 1 "{\"cwd\":\"$TEST_ROOT/wt-x\"}")" \
  "$prefix --token repo=my-repo --token branch=feat/x --token wt=⎇ wt-x"$'\n'"$prefix --clear-token icon --token c0=●"

cwd_changed=$(printf '{"cwd":"%s","new_cwd":"%s"}' "$REPO" "$TEST_ROOT/wt-x")
expect "prefers new_cwd from CwdChanged" \
  "$(run_hook 1 "$cwd_changed")" \
  "$prefix --token repo=my-repo --token branch=feat/x --token wt=⎇ wt-x"$'\n'"$prefix --clear-token icon --token c0=●"

expect "names a submodule after its own checkout, not .git/modules" \
  "$(run_hook 1 "{\"cwd\":\"$SUPER/sub-repo\"}")" \
  "$prefix --token repo=sub-repo --token branch=main --clear-token wt"$'\n'"$prefix --clear-token icon --token c1=●"

expect "names a bare repo worktree after the bare repo" \
  "$(run_hook 1 "{\"cwd\":\"$TEST_ROOT/bare-wt\"}")" \
  "$prefix --token repo=bare-repo --token branch=main --token wt=⎇ bare-wt"$'\n'"$prefix --clear-token icon --token c2=●"

view_requests() {
  : >"$VIEW_LOG"
  run_hook 1 "{\"cwd\":\"$REPO\",\"hook_event_name\":\"SessionStart\",\"source\":\"$1\"}" >/dev/null
  cat "$VIEW_LOG"
}

expect "sorts the agent panel by repo on a fresh session start" \
  "$(view_requests startup)" "agent.view.set repo"

expect "leaves the agent view alone after /clear" \
  "$(view_requests clear)" ""

expect "starts each space at the first color" \
  "$(FAKE_SPACE=space-b run_hook 1 "{\"cwd\":\"$TEST_ROOT/plain2\"}" | grep -o 'c[0-9]*=●')" "c0=●"

for i in $(seq 4 14); do printf 'space-a filler-%s %s\n' "$i" "$((i - 1))" >>"$TEST_ROOT/state/herdr/repo-colors"; done
expect "gives each new repo in a space an unused color, then wraps after 14" \
  "$(run_hook 1 "{\"cwd\":\"$TEST_ROOT/plain2\"}" | grep -o 'c[0-9]*=●')" "c0=●"

expect "clears every token outside a git repo" \
  "$(run_hook 1 "{\"cwd\":\"$TEST_ROOT/plain\"}")" \
  "$prefix --clear-token repo --clear-token branch --clear-token wt"$'\n'"$prefix --clear-token icon"

echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
