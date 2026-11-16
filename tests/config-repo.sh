#!/bin/bash
# Tests for hooks/lib/config-repo.sh. Each case builds its config dir and
# checkout under the suite's temp dir.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
# shellcheck source=../hooks/lib/config-repo.sh
. "$PROJECT_DIR/hooks/lib/config-repo.sh"

harness_init config-repo-lib

CONFIG="$TEST_ROOT/config"
CHECKOUT="$TEST_ROOT/checkout"
mkdir -p "$CONFIG" "$CHECKOUT/hooks" "$CHECKOUT/scripts"
ln -s "$CHECKOUT/hooks" "$CONFIG/hooks"

# resolves <want> <args...>: config_repo_dir <args...> prints <want>.
resolves() {
  local want="$1"
  shift
  [ "$(config_repo_dir "$@")" = "$want" ]
}

unset AGENT_CONFIG_REPO CLAUDE_DOTFILES_REPO

check "the hooks link names the checkout" resolves "$CHECKOUT" "$CONFIG"
check "AGENT_CONFIG_REPO wins over the link" \
  env AGENT_CONFIG_REPO=/override bash -c ". '$PROJECT_DIR/hooks/lib/config-repo.sh'; [ \"\$(config_repo_dir '$CONFIG')\" = /override ]"
check "CLAUDE_DOTFILES_REPO wins over the link" \
  env CLAUDE_DOTFILES_REPO=/legacy bash -c ". '$PROJECT_DIR/hooks/lib/config-repo.sh'; [ \"\$(config_repo_dir '$CONFIG')\" = /legacy ]"
check "AGENT_CONFIG_REPO wins over CLAUDE_DOTFILES_REPO" \
  env AGENT_CONFIG_REPO=/override CLAUDE_DOTFILES_REPO=/legacy bash -c ". '$PROJECT_DIR/hooks/lib/config-repo.sh'; [ \"\$(config_repo_dir '$CONFIG')\" = /override ]"

check "a missing marker rejects the linked checkout" not config_repo_dir "$CONFIG" scripts/setup-hosts.sh
touch "$CHECKOUT/scripts/setup-hosts.sh"
check "a present marker accepts the linked checkout" resolves "$CHECKOUT" "$CONFIG" scripts/setup-hosts.sh

mkdir -p "$TEST_ROOT/unlinked"
check "a config dir without a hooks link resolves nothing" not config_repo_dir "$TEST_ROOT/unlinked"
ln -s relative/hooks "$TEST_ROOT/unlinked/hooks"
check "a relative hooks link resolves nothing" not config_repo_dir "$TEST_ROOT/unlinked"

finish
