# shellcheck shell=bash
# Sourced before every Claude Code Bash command through CLAUDE_ENV_FILE, in
# zsh or bash. It fixes two things the user's interactive profile gets wrong
# for an agent: it picks node from the nearest .nvmrc on every cd, and it drops
# the interactive rm/mv/cp aliases whose prompts hang a non-interactive shell.

unalias rm mv cp 2>/dev/null

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
  rest=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v "/.nvm/versions/node/" | paste -sd: -)
  export PATH="$match/bin${rest:+:$rest}"
}

if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook chpwd _agent_nvmrc_node
else
  cd() { builtin cd "$@" && _agent_nvmrc_node; }
fi
_agent_nvmrc_node
