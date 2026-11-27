#!/bin/bash
# Tests for scripts/config-integrity.sh and the strip filter it prints. Each
# case commits a settings.json into a scratch repo that holds a copy of the
# script, because the script checks the repo it sits in.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"

harness_init config-integrity

# repo_with <name> <settings-json>: a repo whose first commit holds the script,
# .gitattributes, and that settings.json.
repo_with() {
  local dir="$TEST_ROOT/$1"
  mkdir -p "$dir/scripts"
  cp "$PROJECT_DIR/scripts/config-integrity.sh" "$dir/scripts/"
  cp "$PROJECT_DIR/.gitattributes" "$dir/"
  printf '%s\n' "$2" > "$dir/settings.json"
  make_repo "$dir" >/dev/null
  echo "$dir"
}

allow_repo=$(repo_with allow '{"autoMode":{"allow":["$defaults","rule"]}}')
expect_exit "committed autoMode.allow rules pass" 0 bash "$allow_repo/scripts/config-integrity.sh"

env_repo=$(repo_with env '{"autoMode":{"allow":["rule"],"environment":["host"]}}')
expect_exit --says "carries autoMode.environment" \
  "a committed autoMode.environment fails" 1 bash "$env_repo/scripts/config-integrity.sh"

state_repo=$(repo_with state '{"lastChangelogVersion":"1.0.0"}')
expect_exit --says "carries lastChangelogVersion" \
  "a committed top-level runtime key fails" 1 bash "$state_repo/scripts/config-integrity.sh"

# The filter the script prints, minus its `|| cat` fallback, run as git would.
filter_program() {
  sed -n "s/^STRIP_FILTER='jq \"\(.*\)\" 2>.*/\1/p" "$PROJECT_DIR/scripts/config-integrity.sh"
}
strips() {
  [ "$(printf '%s' "$1" | jq -c "$(filter_program)")" = "$2" ]
}

check "the filter drops autoMode.environment and keeps allow" \
  strips '{"autoMode":{"allow":["r"],"environment":["h"]}}' '{"autoMode":{"allow":["r"]}}'
check "the filter drops an autoMode left empty" \
  strips '{"a":1,"autoMode":{"environment":["h"]}}' '{"a":1}'
check "the filter drops top-level runtime keys" \
  strips '{"a":1,"feedbackSurveyState":{},"lastChangelogVersion":"1"}' '{"a":1}'
check "the README carries the same filter as the script" \
  grep -qF "$(filter_program)" "$PROJECT_DIR/README.md"

finish
