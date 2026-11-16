#!/bin/bash
# Tests for hooks/config-autoupdate.sh. Each scenario clones a local bare
# remote, so no network is used.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
HOOK="$PROJECT_DIR/hooks/config-autoupdate.sh"

harness_init config-autoupdate

# setup: a remote with one commit, a clone of it, then one more commit on the
# remote that the clone has not seen.
setup() {
  rm -rf "$TEST_ROOT/remote.git" "$TEST_ROOT/seed" "$TEST_ROOT/clone"
  make_repo "$TEST_ROOT/seed"
  git clone -q --bare "$TEST_ROOT/seed" "$TEST_ROOT/remote.git"
  git clone -q "$TEST_ROOT/remote.git" "$TEST_ROOT/clone"
  echo merged > "$TEST_ROOT/seed/file"
  git -C "$TEST_ROOT/seed" add file
  git -C "$TEST_ROOT/seed" commit -q -m "feat: merged change"
  git -C "$TEST_ROOT/seed" push -q "$TEST_ROOT/remote.git" main
}

run() {
  OUT=$(AGENT_CONFIG_REPO="$TEST_ROOT/clone" bash "$HOOK" 2>&1)
  STATUS=$?
}

up_to_date() { [ "$(git -C "$TEST_ROOT/clone" rev-parse HEAD)" = "$(git -C "$TEST_ROOT/remote.git" rev-parse main)" ]; }

setup
run
check "a clean checkout on main fast-forwards" up_to_date
check "the update is reported" exited 0 says "Updated agent config"

run
check "an up-to-date checkout prints nothing" exited 0 [ -z "$OUT" ]

setup
git -C "$TEST_ROOT/clone" switch -q -c fix/x
run
check "a checkout on another branch stays put" not up_to_date
check "the branch case says why" exited 0 says "is on fix/x"

setup
echo local > "$TEST_ROOT/clone/README"
git -C "$TEST_ROOT/clone" add README
run
check "a checkout with local changes stays put" not up_to_date
check "the local-changes case says why" exited 0 says "has local changes"

setup
echo scratch > "$TEST_ROOT/clone/untracked"
run
check "an untracked file does not block the update" up_to_date

setup
OUT=$(AGENT_CONFIG_REPO="$TEST_ROOT/clone" SKIP_CONFIG_AUTOUPDATE=1 bash "$HOOK" 2>&1)
check "SKIP_CONFIG_AUTOUPDATE turns it off" not up_to_date

OUT=$(AGENT_CONFIG_REPO="$TEST_ROOT/missing" bash "$HOOK" 2>&1)
STATUS=$?
check "a missing checkout exits quietly" exited 0 [ -z "$OUT" ]

finish
