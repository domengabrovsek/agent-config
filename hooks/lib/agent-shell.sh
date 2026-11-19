# shellcheck shell=bash
# Sourced before every Claude Code Bash command through CLAUDE_ENV_FILE, in
# zsh or bash. It fixes what the user's interactive profile gets wrong for an
# agent: it picks node from the nearest .nvmrc on every cd, drops the
# interactive rm/mv/cp aliases whose prompts hang a non-interactive shell, and
# puts sandbox-safe tool shims first on PATH.

unalias rm mv cp 2>/dev/null

# bin/ holds shims for system tools that misbehave under the sandbox. zsh sets
# $0 to the sourced file; bash needs BASH_SOURCE.
_agent_bin="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/bin"
case ":$PATH:" in
  *":$_agent_bin:"*) ;;
  *) export PATH="$_agent_bin:$PATH" ;;
esac
unset _agent_bin

# Agents get their own cache root, the only writable dir under ~/.cache. Your
# own tools never read it, so a poisoned cache entry or a hook planted in a
# cached clone cannot run outside the sandbox through them.
export XDG_CACHE_HOME="$HOME/.cache/agent"
[ -d "$XDG_CACHE_HOME" ] || mkdir -p "$XDG_CACHE_HOME" 2>/dev/null

# _agent_nvmrc_node: puts the node named by the nearest .nvmrc first on PATH.
# A partial version such as `26` picks the newest installed match. An alias
# such as `lts/*` or a version that is not installed leaves PATH unchanged.
_agent_nvmrc_node() {
  local dir="$PWD" want="" match="" candidate rest
  [ -n "${ZSH_VERSION:-}" ] && setopt local_options null_glob
  while [ -n "$dir" ]; do
    if [ -f "$dir/.nvmrc" ]; then
      want=$(tr -d ' \t\r\n' < "$dir/.nvmrc")
      break
    fi
    [ "$dir" = / ] && break
    dir=$(dirname "$dir")
  done
  want=${want#v}
  case "$want" in
    '' | *[!0-9.]*) return 0 ;;
  esac
  for candidate in "${NVM_DIR:-$HOME/.nvm}/versions/node/v$want" "${NVM_DIR:-$HOME/.nvm}/versions/node/v$want".*; do
    [ -x "$candidate/bin/node" ] || continue
    if [ -z "$match" ] || [ "$(printf '%s\n%s\n' "${match##*/v}" "${candidate##*/v}" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "${candidate##*/v}" ]; then
      match=$candidate
    fi
  done
  [ -n "$match" ] || return 0
  rest=$(printf '%s' "$PATH" | tr ':' '\n' | grep -vF "${NVM_DIR:-$HOME/.nvm}/versions/node/" | paste -sd: -)
  export PATH="$match/bin${rest:+:$rest}"
}

if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook chpwd _agent_nvmrc_node
else
  cd() { builtin cd "$@" && _agent_nvmrc_node; }
fi
_agent_nvmrc_node
