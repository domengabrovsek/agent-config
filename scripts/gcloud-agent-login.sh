#!/bin/bash
# Mint short-lived impersonated tokens for AI agents into a gcloud config that
# holds no user credential. Run it in your own terminal, never inside an agent
# session: the Claude Code sandbox blocks reads of your gcloud login.
#
# Usage: scripts/gcloud-agent-login.sh [--help]
#
# Targets come from <agent config>/targets, one per line:
#   <configuration-name> <service-account-email> <project-id>
# The first line becomes the active configuration. Lines starting with # are
# skipped. Tokens last about one hour; run the script again to refresh them.
#
# Environment:
#   GCLOUD_USER_CONFIG   Your own gcloud config dir (default: ~/.config/gcloud).
#   GCLOUD_AGENT_CONFIG  The agents' gcloud config dir (default: ~/.config/gcloud-agent).

set -euo pipefail

USER_CONFIG="${GCLOUD_USER_CONFIG:-$HOME/.config/gcloud}"
AGENT_CONFIG="${GCLOUD_AGENT_CONFIG:-$HOME/.config/gcloud-agent}"
TARGETS="$AGENT_CONFIG/targets"

case "${1:-}" in
  -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "Unknown argument: $1" >&2; exit 2 ;;
esac

if [ ! -f "$TARGETS" ]; then
  echo "No targets file at $TARGETS. Add one line per target:" >&2
  echo "  <configuration-name> <service-account-email> <project-id>" >&2
  exit 1
fi

umask 077
mkdir -p "$AGENT_CONFIG/tokens"

agent_gcloud() { CLOUDSDK_CONFIG="$AGENT_CONFIG" gcloud --quiet "$@"; }

FIRST=""
while read -r name sa project _; do
  case "$name" in ''|'#'*) continue ;; esac
  if [ -z "$sa" ] || [ -z "$project" ]; then
    echo "Skipping malformed line for '$name' in $TARGETS" >&2
    continue
  fi

  token_file="$AGENT_CONFIG/tokens/$name"
  if ! token=$(CLOUDSDK_CONFIG="$USER_CONFIG" gcloud auth print-access-token \
      --impersonate-service-account="$sa" 2>"$token_file.err"); then
    cat "$token_file.err" >&2
    rm -f "$token_file.err"
    echo "Could not mint a token for $sa. Run this in your own terminal, signed in with gcloud auth login." >&2
    exit 1
  fi
  rm -f "$token_file.err"
  printf '%s\n' "$token" > "$token_file"

  agent_gcloud config configurations describe "$name" >/dev/null 2>&1 \
    || agent_gcloud config configurations create "$name" --no-activate >/dev/null 2>&1
  agent_gcloud config set auth/access_token_file "$token_file" --configuration="$name" >/dev/null 2>&1
  agent_gcloud config set core/project "$project" --configuration="$name" >/dev/null 2>&1

  [ -n "$FIRST" ] || FIRST="$name"
  echo "$name: $sa on $project"
done < "$TARGETS"

if [ -z "$FIRST" ]; then
  echo "No targets in $TARGETS" >&2
  exit 1
fi

agent_gcloud config configurations activate "$FIRST" >/dev/null 2>&1
echo "Active: $FIRST. Tokens expire in about an hour; run this again to refresh."
