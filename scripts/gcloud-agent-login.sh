#!/bin/bash
# Mint short-lived impersonated tokens for AI agents into a gcloud config that
# holds no user credential. Run it in your own terminal. Agents may run only
# the exact sandbox-excluded form, `~/.agents/scripts/gcloud-agent-login.sh
# nonprod`, because the sandbox blocks reads of your gcloud login.
#
# Usage: scripts/gcloud-agent-login.sh [--help] [<target>...]
#
# Targets come from ~/.config/gcloud-agent/targets, one per line:
#   <configuration-name> <service-account-email> <project-id>
# Lines starting with # are skipped. With no argument, it refreshes every
# target and activates the first line. With target names, it only rewrites
# their token files, leaves the active configuration alone, and fails on an
# unknown name or one with no configuration yet.
# Tokens last about one hour; run the script again to refresh them.
#
# The config dirs and the gcloud binary are fixed, and PATH is reset, because
# agents can run this outside the sandbox and control their environment.

set -euo pipefail

# The test suite rewrites this line to point at a stub.
GCLOUD_CANDIDATES="/opt/homebrew/bin/gcloud /usr/local/bin/gcloud /usr/bin/gcloud"

USER_CONFIG="$HOME/.config/gcloud"
AGENT_CONFIG="$HOME/.config/gcloud-agent"
TARGETS="$AGENT_CONFIG/targets"

for arg in "$@"; do
  case "$arg" in
    -h|--help) sed -n '2,/^[^#]/s/^# \{0,1\}//p' "$0"; exit 0 ;;
    -*) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

GCLOUD=""
for candidate in $GCLOUD_CANDIDATES; do
  if [ -x "$candidate" ]; then GCLOUD="$candidate"; break; fi
done
if [ -z "$GCLOUD" ]; then
  echo "No gcloud found at: $GCLOUD_CANDIDATES" >&2
  exit 1
fi

# gcloud finds its Python through PATH and CLOUDSDK_PYTHON, so neither may come
# from the caller.
PATH="$(dirname "$GCLOUD"):/usr/bin:/bin"
export PATH
unset CLOUDSDK_PYTHON CLOUDSDK_PYTHON_ARGS

if [ ! -f "$TARGETS" ]; then
  echo "No targets file at $TARGETS. Add one line per target:" >&2
  echo "  <configuration-name> <service-account-email> <project-id>" >&2
  exit 1
fi

# wanted <name>: true when every target is wanted or <name> was asked for.
wanted() {
  local name="$1" want
  shift
  [ "$#" -gt 0 ] || return 0
  for want in "$@"; do [ "$want" = "$name" ] && return 0; done
  return 1
}

for want in "$@"; do
  if ! awk -v n="$want" '$1 == n && $2 != "" && $3 != "" { found = 1 } END { exit !found }' "$TARGETS"; then
    echo "Unknown target: $want (not in $TARGETS)" >&2
    exit 2
  fi
done

umask 077
mkdir -p "$AGENT_CONFIG/tokens"

agent_gcloud() { CLOUDSDK_CONFIG="$AGENT_CONFIG" "$GCLOUD" --quiet "$@"; }

# step <target> <what> <gcloud args...>: runs one agent-config call and names
# the target and step when it fails, with gcloud's own error.
step() {
  local target="$1" what="$2" err
  shift 2
  if ! err=$(agent_gcloud "$@" 2>&1 >/dev/null); then
    printf '%s\n' "$err" >&2
    echo "Failed to $what for target '$target'." >&2
    exit 1
  fi
}

FIRST=""
while read -r name sa project _ <&3; do
  case "$name" in ''|'#'*) continue ;; esac
  if [ -z "$sa" ] || [ -z "$project" ]; then
    echo "Skipping malformed line for '$name' in $TARGETS" >&2
    continue
  fi
  wanted "$name" "$@" || continue
  if [ "$#" -gt 0 ] && [ ! -f "$AGENT_CONFIG/configurations/config_$name" ]; then
    echo "No configuration '$name' yet. Run this with no argument in your own terminal first." >&2
    exit 1
  fi

  token_file="$AGENT_CONFIG/tokens/$name"
  if ! token=$(CLOUDSDK_CONFIG="$USER_CONFIG" "$GCLOUD" auth print-access-token \
      --impersonate-service-account="$sa" 2>"$token_file.err"); then
    cat "$token_file.err" >&2
    rm -f "$token_file.err"
    echo "Could not mint a token for $sa. Run this in your own terminal, signed in with gcloud auth login." >&2
    exit 1
  fi
  rm -f "$token_file.err"
  printf '%s\n' "$token" > "$token_file"

  # A named refresh runs no gcloud against the agent config: agents can write
  # that dir, so gcloud there could follow a planted symlink outside the sandbox.
  if [ "$#" -eq 0 ]; then
    agent_gcloud config configurations describe "$name" >/dev/null 2>&1 \
      || step "$name" "create the configuration" config configurations create "$name" --no-activate
    step "$name" "set the token file" config set auth/access_token_file "$token_file" --configuration="$name"
    step "$name" "set the project" config set core/project "$project" --configuration="$name"
  fi

  [ -n "$FIRST" ] || FIRST="$name"
  echo "$name: $sa on $project"
done 3< "$TARGETS"

if [ -z "$FIRST" ]; then
  echo "No targets in $TARGETS" >&2
  exit 1
fi

if [ "$#" -gt 0 ]; then
  echo "Refreshed: $*. Tokens expire in about an hour; run this again to refresh."
  exit 0
fi

step "$FIRST" "activate the configuration" config configurations activate "$FIRST"
echo "Active: $FIRST. Tokens expire in about an hour; run this again to refresh."
