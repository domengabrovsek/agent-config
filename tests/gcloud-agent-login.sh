#!/usr/bin/env bash
# Tests for scripts/gcloud-agent-login.sh against a stub gcloud that records
# each call, so no real credential or network is touched.

set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
SCRIPT="$PROJECT_DIR/scripts/gcloud-agent-login.sh"
harness_init gcloud-agent-login
OUT=""
STATUS=0

BIN="$TEST_ROOT/bin"
LOG="$TEST_ROOT/calls.log"
export GCLOUD_USER_CONFIG="$TEST_ROOT/user"
export GCLOUD_AGENT_CONFIG="$TEST_ROOT/agent"

# The stub prints a token named after the impersonated SA, fails minting when
# STUB_MINT_FAIL is set, and logs which config dir each call used. Minting
# drains stdin, as a reauth prompt can, so a loop sharing stdin
# with the targets file loses a target.
stub "$BIN" gcloud <<'EOF'
#!/bin/bash
printf '%s|%s\n' "$CLOUDSDK_CONFIG" "$*" >> "$STUB_LOG"
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
export PATH="$BIN:$PATH" STUB_LOG="$LOG"

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

mkdir -p "$GCLOUD_AGENT_CONFIG"
cat > "$GCLOUD_AGENT_CONFIG/targets" <<'EOF'
# comment
nonprod agent@staging.iam.gserviceaccount.com staging-project

production agent@prod.iam.gserviceaccount.com prod-project
EOF

run
check "mints a token per target" exited 0 says "nonprod: agent@staging" says "production: agent@prod"
check "writes the nonprod token" grep -qx "token-for-agent@staging.iam.gserviceaccount.com" "$GCLOUD_AGENT_CONFIG/tokens/nonprod"
check "token file is private" test "$(stat -c %a "$GCLOUD_AGENT_CONFIG/tokens/nonprod" 2>/dev/null || stat -f %Lp "$GCLOUD_AGENT_CONFIG/tokens/nonprod")" = 600
check "mints with the user config" logged "$GCLOUD_USER_CONFIG|auth print-access-token --impersonate-service-account=agent@prod"
check "points the agent config at the token file" logged "$GCLOUD_AGENT_CONFIG|--quiet config set auth/access_token_file $GCLOUD_AGENT_CONFIG/tokens/production --configuration=production"
check "sets the project" logged "--quiet config set core/project staging-project --configuration=nonprod"
check "activates the first target" logged "--quiet config configurations activate nonprod"
check "agent config never mints" not grep -q "^$GCLOUD_AGENT_CONFIG|auth print-access-token" "$LOG"

STUB_MINT_FAIL=1 run
check "a failed mint stops with a hint" exited 1 says "own terminal" says "denied"

STUB_SET_FAIL=1 run
check "a failed config step names the target and step" exited 1 says "bad project" says "set the project for target 'nonprod'"

run --bogus
check "rejects unknown arguments" exited 2

finish
