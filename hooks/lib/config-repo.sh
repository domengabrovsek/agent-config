#!/bin/bash
# Shared lookup of the agent config checkout for the session hooks.
#
# The hook's own path is not enough: a session may run a second clone's copy
# under CLAUDE_PROJECT_DIR, while the config dir still links into the checkout
# the bootstrap set up. So the lookup reads that link, as the bootstrap wrote it.

# config_repo_dir <config-dir> [marker]
# Prints AGENT_CONFIG_REPO, else CLAUDE_DOTFILES_REPO, else the checkout that
# <config-dir>/hooks links into. With [marker], the linked checkout counts only
# when it holds that file. Fails when none applies.
config_repo_dir() {
  local link repo
  repo="${AGENT_CONFIG_REPO:-${CLAUDE_DOTFILES_REPO:-}}"
  if [ -z "$repo" ]; then
    link=$(readlink "$1/hooks" 2>/dev/null)
    case "$link" in
      /*) repo="${link%/hooks}" ;;
    esac
    if [ -n "$repo" ] && [ -n "${2:-}" ] && [ ! -e "$repo/$2" ]; then
      repo=""
    fi
  fi
  [ -n "$repo" ] || return 1
  printf '%s\n' "$repo"
}
