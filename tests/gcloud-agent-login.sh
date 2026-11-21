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
REAL_HOME="$TEST_ROOT/home"
USER_CONFIG="$REAL_HOME/.config/gcloud"
AGENT_CONFIG="$REAL_HOME/.config/gcloud-agent"
# A caller's HOME must not matter, so the suite runs with a different one.
export HOME="$TEST_ROOT/caller-home"

# The script fixes HOME and its gcloud and python paths, so the suite runs a
# copy whose lines point at stubs.
SCRIPT="$TEST_ROOT/gcloud-agent-login.sh"
sed -e "s|^GCLOUD_CANDIDATES=.*|GCLOUD_CANDIDATES=\"$BIN/gcloud\"|" \
  -e "s|^PYTHON_CANDIDATES=.*|PYTHON_CANDIDATES=\"$TEST_ROOT/missing/python3 $BIN/python3\"|" \
  -e "s|^HOME=\$(passwd_home)\$|HOME=\"$REAL_HOME\"|" \
  "$PROJECT_DIR/scripts/gcloud-agent-login.sh" > "$SCRIPT"
chmod +x "$SCRIPT"

# The script runs gcloud with an empty environment, so the stub finds its log
# and failure flags next to its own dir. It prints a token named after the
# impersonated SA, and logs the config dir, arguments, PATH, CLOUDSDK_PYTHON,
# and any leaked variable of each call. Minting drains stdin, as a reauth
# prompt can, so a loop sharing stdin with the targets file loses a target.
stub "$BIN" gcloud <<'EOF'
#!/bin/bash
root=$(cd "$(dirname "$0")/.." && pwd)
printf '%s|%s|%s\n' "$CLOUDSDK_CONFIG" "$*" "$PATH${CLOUDSDK_PYTHON:+|py=$CLOUDSDK_PYTHON}${CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE:+|leak=ca}${PYTHONPATH:+|leak=pythonpath}" >> "$root/calls.log"
case "$*" in
  *print-access-token*)
    cat >/dev/null
    [ ! -e "$root/mint-fail" ] || { echo "denied" >&2; exit 1; }
    for a in "$@"; do case "$a" in --impersonate-service-account=*) echo "token-for-${a#*=}" ;; esac; done ;;
  *"configurations describe"*) exit 1 ;;
  *"core/project"*) [ ! -e "$root/set-fail" ] || { echo "bad project" >&2; exit 1; } ;;
esac
exit 0
EOF
stub "$BIN" python3 <<'EOF'
#!/bin/bash
exit 0
EOF
stub "$DECOY" gcloud <<'EOF'
#!/bin/bash
echo "decoy gcloud ran" >> "$(cd "$(dirname "$0")/.." && pwd)/calls.log"
EOF
export PATH="$DECOY:$PATH"

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

touch "$TEST_ROOT/mint-fail"
run
rm "$TEST_ROOT/mint-fail"
check "a failed mint stops with a hint" exited 1 says "own terminal" says "denied"

touch "$TEST_ROOT/set-fail"
run
rm "$TEST_ROOT/set-fail"
check "a failed config step names the target and step" exited 1 says "bad project" says "set the project for target 'nonprod'"

run --bogus
check "rejects unknown options" exited 2

run nonprod
check "a named refresh needs an existing configuration" exited 1 says "no argument in your own terminal"
check "a named refresh without a configuration mints nothing" not logged "print-access-token"

# The stub creates no configuration files, so the suite adds the ones a full
# run leaves behind.
mkdir -p "$AGENT_CONFIG/configurations"
touch "$AGENT_CONFIG/configurations/config_nonprod" "$AGENT_CONFIG/configurations/config_production"
rm -f "$AGENT_CONFIG/tokens/nonprod"

run nonprod
check "refreshes only the named target" exited 0 says "nonprod: agent@staging" not says "production:"
check "a named refresh rewrites the token" grep -qx "token-for-agent@staging.iam.gserviceaccount.com" "$AGENT_CONFIG/tokens/nonprod"
check "skips minting other targets" not logged "impersonate-service-account=agent@prod"
check "a named refresh runs no gcloud on the agent config" not logged "$AGENT_CONFIG|"

run nonprod production
check "rejects more than one target" exited 2 says "one target at most"
check "more than one target mints nothing" not logged "print-access-token"

run staging
check "an unknown target fails" exited 2 says "Unknown target: staging"
check "an unknown target mints nothing" not logged "print-access-token"

GCLOUD_USER_CONFIG="$TEST_ROOT/other-user" GCLOUD_AGENT_CONFIG="$TEST_ROOT/other-agent" run nonprod
check "ignores config dir overrides" logged "$USER_CONFIG|auth print-access-token"
check "never writes an overridden agent dir" not test -e "$TEST_ROOT/other-agent"
check "ignores the caller's HOME" not logged "$TEST_ROOT/caller-home"
check "the rewritten copy replaced the HOME lookup" not grep -q 'passwd_home)$' "$SCRIPT"
PASSWD_HOME_FN=$(sed -n '/^passwd_home()/,/^}/p' "$PROJECT_DIR/scripts/gcloud-agent-login.sh")
check "passwd_home ignores HOME" test "$(HOME=/nowhere bash -c "$PASSWD_HOME_FN"'
passwd_home')" = "$(eval "printf '%s' ~$(id -un)")"

CLOUDSDK_PYTHON="$DECOY/python3" run nonprod
check "never runs a gcloud found on PATH" not logged "decoy gcloud ran"
check "resets PATH for gcloud" not logged "$DECOY"
check "pins CLOUDSDK_PYTHON to the first fixed python" logged "|py=$BIN/python3"
check "ignores a caller's CLOUDSDK_PYTHON" not logged "py=$DECOY"

echo 'echo bash-env-ran >> "$LOG_PATH"' > "$TEST_ROOT/bash-env"
LOG_PATH="$LOG" BASH_ENV="$TEST_ROOT/bash-env" CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE=/x PYTHONPATH=/x run nonprod
check "drops caller variables before gcloud" exited 0 not logged "leak="
check "never reads BASH_ENV" not logged "bash-env-ran"

ln -s "$TEST_ROOT/victim" "$AGENT_CONFIG/active_config"
run nonprod
check "refuses to run while the agent config holds a symlink" exited 1 says "holds a symlink"
check "a planted symlink stops every gcloud call" not logged "|"
rm "$AGENT_CONFIG/active_config"

finish
