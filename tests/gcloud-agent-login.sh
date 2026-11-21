#!/usr/bin/env bash
# Tests for scripts/gcloud-agent-login.sh against a stub gcloud that records
# each call, so no real credential or network is touched.

set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
harness_init gcloud-agent-login
OUT=""
STATUS=0

BIN="$TEST_ROOT/bin"
DECOY="$TEST_ROOT/decoy"
LOG="$TEST_ROOT/calls.log"
export HOME="$TEST_ROOT/home"
USER_CONFIG="$HOME/.config/gcloud"
AGENT_CONFIG="$HOME/.config/gcloud-agent"

# The script fixes its gcloud path, so the suite runs a copy whose candidate
# list points at the stub.
SCRIPT="$TEST_ROOT/gcloud-agent-login.sh"
sed "s|^GCLOUD_CANDIDATES=.*|GCLOUD_CANDIDATES=\"$BIN/gcloud\"|" \
  "$PROJECT_DIR/scripts/gcloud-agent-login.sh" > "$SCRIPT"
chmod +x "$SCRIPT"

# The stub prints a token named after the impersonated SA, fails minting when
# STUB_MINT_FAIL is set, and logs the config dir, arguments, PATH, and any
# CLOUDSDK_PYTHON of each call. Minting drains stdin, as a reauth prompt can,
# so a loop sharing stdin with the targets file loses a target.
stub "$BIN" gcloud <<'EOF'
#!/bin/bash
printf '%s|%s|%s\n' "$CLOUDSDK_CONFIG" "$*" "$PATH${CLOUDSDK_PYTHON:+|py=$CLOUDSDK_PYTHON}" >> "$STUB_LOG"
case "$*" in
  *print-access-token*)
    cat >/dev/null
    [ -z "${STUB_MINT_FAIL:-}" ] || { echo "denied" >&2; exit 1; }
    for a in "$@"; do case "$a" in --impersonate-service-account=*) echo "token-for-${a#*=}" ;; esac; done ;;
  *"configurations describe"*) exit 1 ;;
  *"core/project"*) [ -z "${STUB_SET_FAIL:-}" ] || { echo "bad project" >&2; exit 1; } ;;
esac
exit 0
EOF
stub "$DECOY" gcloud <<'EOF'
#!/bin/bash
echo "decoy gcloud ran" >> "$STUB_LOG"
EOF
export PATH="$DECOY:$PATH" STUB_LOG="$LOG"

# run [arg...]: sets OUT and STATUS, which the harness predicates read.
# shellcheck disable=SC2034
run() {
  : > "$LOG"
  set +e
  OUT=$("$SCRIPT" "$@" 2>&1 </dev/null)
  STATUS=$?
  set -e
}

logged() { grep -qF -- "$1" "$LOG"; }

run
check "missing targets file fails with the expected format" exited 1 says "<configuration-name>"

mkdir -p "$AGENT_CONFIG"
cat > "$AGENT_CONFIG/targets" <<'EOF'
# comment
nonprod agent@staging.iam.gserviceaccount.com staging-project

production agent@prod.iam.gserviceaccount.com prod-project
EOF

run
check "mints a token per target" exited 0 says "nonprod: agent@staging" says "production: agent@prod"
check "writes the nonprod token" grep -qx "token-for-agent@staging.iam.gserviceaccount.com" "$AGENT_CONFIG/tokens/nonprod"
check "token file is private" test "$(stat -c %a "$AGENT_CONFIG/tokens/nonprod" 2>/dev/null || stat -f %Lp "$AGENT_CONFIG/tokens/nonprod")" = 600
check "mints with the user config" logged "$USER_CONFIG|auth print-access-token --impersonate-service-account=agent@prod"
check "points the agent config at the token file" logged "$AGENT_CONFIG|--quiet config set auth/access_token_file $AGENT_CONFIG/tokens/production --configuration=production"
check "sets the project" logged "--quiet config set core/project staging-project --configuration=nonprod"
check "activates the first target" logged "--quiet config configurations activate nonprod"
check "agent config never mints" not grep -q "^$AGENT_CONFIG|auth print-access-token" "$LOG"

STUB_MINT_FAIL=1 run
check "a failed mint stops with a hint" exited 1 says "own terminal" says "denied"

STUB_SET_FAIL=1 run
check "a failed config step names the target and step" exited 1 says "bad project" says "set the project for target 'nonprod'"

run --bogus
check "rejects unknown options" exited 2

run nonprod
check "refreshes only the named target" exited 0 says "nonprod: agent@staging" not says "production:"
check "skips minting other targets" not logged "impersonate-service-account=agent@prod"
check "a named refresh keeps the active configuration" not logged "configurations activate"

run nonprod production
check "refreshes several named targets" exited 0 says "nonprod:" says "production:"

run staging
check "an unknown target fails" exited 2 says "Unknown target: staging"
check "an unknown target mints nothing" not logged "print-access-token"

GCLOUD_USER_CONFIG="$TEST_ROOT/other-user" GCLOUD_AGENT_CONFIG="$TEST_ROOT/other-agent" run nonprod
check "ignores config dir overrides" logged "$USER_CONFIG|auth print-access-token"
check "never writes an overridden agent dir" not test -e "$TEST_ROOT/other-agent"

CLOUDSDK_PYTHON="$DECOY/python3" run nonprod
check "never runs a gcloud found on PATH" not logged "decoy gcloud ran"
check "resets PATH for gcloud" not logged "$DECOY"
check "drops CLOUDSDK_PYTHON" not logged "py="

finish
