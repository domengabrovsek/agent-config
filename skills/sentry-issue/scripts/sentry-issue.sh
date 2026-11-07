#!/usr/bin/env bash
set -euo pipefail

# Fetch a Sentry issue + latest event by short ID, numeric ID, or issue URL.
# Org-agnostic: resolves token/org/url from env, project .sentryclirc, ~/.sentryclirc,
# or auto-discovers the org via the API. The auth token is never printed.

usage() {
  echo "usage: sentry-issue.sh <SHORT_ID|ISSUE_ID|SENTRY_URL> [--org <slug>]" >&2
  exit 1
}

[ $# -ge 1 ] || usage
INPUT="$1"; shift
ORG="${SENTRY_ORG:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --org) ORG="$2"; shift 2 ;;
    *) usage ;;
  esac
done

rc_value() {
  local key="$1" file
  for file in ./.sentryclirc "$(git rev-parse --show-toplevel 2>/dev/null)/.sentryclirc" "$HOME/.sentryclirc"; do
    [ -f "$file" ] || continue
    local val
    val=$(grep -m1 -E "^${key}[[:space:]]*=" "$file" | cut -d= -f2- | tr -d ' ') || true
    if [ -n "$val" ]; then echo "$val"; return 0; fi
  done
  return 0
}

TOKEN="${SENTRY_AUTH_TOKEN:-$(rc_value token)}"
[ -n "$TOKEN" ] || { echo "error: no token found (SENTRY_AUTH_TOKEN, ./.sentryclirc, ~/.sentryclirc)" >&2; exit 1; }
BASE="${SENTRY_URL:-$(rc_value url)}"
BASE="${BASE:-https://sentry.io}"
BASE="${BASE%/}"
[ -n "$ORG" ] || ORG=$(rc_value org)

api() {
  local path="$1" out="$2"
  curl -s -o "$out" -w '%{http_code}' -H "Authorization: Bearer $TOKEN" "$BASE/api/0$path"
}

api_ok() {
  local path="$1" out="$2" code
  code=$(api "$path" "$out")
  if [ "$code" != "200" ]; then
    echo "error: GET $path returned HTTP $code" >&2
    jq -r '.detail // empty' "$out" >&2 2>/dev/null || true
    exit 1
  fi
}

discover_orgs() {
  api_ok "/organizations/" /tmp/sentry-orgs.json
  jq -r '.[].slug' /tmp/sentry-orgs.json
}

ISSUE_ID=""
if [[ "$INPUT" =~ ^https?:// ]]; then
  ISSUE_ID=$(echo "$INPUT" | grep -oE 'issues/[0-9]+' | cut -d/ -f2) || true
  [ -n "$ISSUE_ID" ] || { echo "error: could not extract issue ID from URL" >&2; exit 1; }
  if [ -z "$ORG" ]; then
    ORG=$(echo "$INPUT" | sed -nE 's#https?://([^./]+)\.sentry\.io.*#\1#p')
  fi
elif [[ "$INPUT" =~ ^[0-9]+$ ]]; then
  ISSUE_ID="$INPUT"
fi
SHORT_ID=$(echo "$INPUT" | tr '[:lower:]' '[:upper:]')

if [ -z "$ORG" ]; then
  ORGS=$(discover_orgs)
  COUNT=$(echo "$ORGS" | grep -c . || true)
  if [ "$COUNT" -eq 1 ]; then
    ORG="$ORGS"
  elif [ -n "$ISSUE_ID" ]; then
    echo "error: multiple orgs ($(echo "$ORGS" | tr '\n' ' ')) - pass --org" >&2
    exit 1
  else
    for candidate in $ORGS; do
      code=$(api "/organizations/$candidate/shortids/$SHORT_ID/" /tmp/sentry-shortid.json)
      if [ "$code" = "200" ]; then ORG="$candidate"; ISSUE_ID=$(jq -r '.groupId' /tmp/sentry-shortid.json); break; fi
    done
    [ -n "$ORG" ] || { echo "error: short ID $SHORT_ID not found in any org ($(echo "$ORGS" | tr '\n' ' '))" >&2; exit 1; }
  fi
fi

if [ -z "$ISSUE_ID" ]; then
  api_ok "/organizations/$ORG/shortids/$SHORT_ID/" /tmp/sentry-shortid.json
  ISSUE_ID=$(jq -r '.groupId' /tmp/sentry-shortid.json)
fi

ISSUE_JSON="/tmp/sentry-issue-$ISSUE_ID.json"
EVENT_JSON="/tmp/sentry-event-$ISSUE_ID.json"
api_ok "/organizations/$ORG/issues/$ISSUE_ID/" "$ISSUE_JSON"
api_ok "/organizations/$ORG/issues/$ISSUE_ID/events/latest/" "$EVENT_JSON"

echo "=== ISSUE ==="
jq -r '
  "shortId:    \(.shortId)",
  "title:      \(.title)",
  "culprit:    \(.culprit)",
  "project:    \(.project.slug)",
  "level:      \(.level)   status: \(.status)   handled: \(.isUnhandled | if . then "no (unhandled)" else "yes" end)",
  "events:     \(.count)   users: \(.userCount)",
  "firstSeen:  \(.firstSeen)",
  "lastSeen:   \(.lastSeen)",
  "permalink:  \(.permalink)"
' "$ISSUE_JSON"

echo ""
echo "=== LATEST EVENT ==="
jq -r '
  "eventID:    \(.eventID)",
  "date:       \(.dateCreated)",
  "message:    \(.message // .title // "-")"
' "$EVENT_JSON"

echo ""
echo "--- tags ---"
jq -r '.tags[] | "\(.key)=\(.value)"' "$EVENT_JSON"

echo ""
echo "--- exception ---"
jq -r '
  [.entries[] | select(.type=="exception") | .data.values[]] | reverse | .[] |
  "\(.type): \(.value)",
  (
    (.stacktrace.frames // []) as $all |
    ([$all[] | select(.inApp == true)] | if length > 0 then . else $all[-10:] end) | reverse | .[] |
    "  \(if .inApp then "[app] " else "" end)\(.filename):\(.lineNo) in \(.function)"
  ),
  ""
' "$EVENT_JSON"

echo "--- request ---"
jq -r '
  [.entries[] | select(.type=="request") | .data] | .[0] // empty |
  "\(.method // "-") \(.url // "-")"
' "$EVENT_JSON"

echo ""
echo "--- breadcrumbs (last 10) ---"
jq -r '
  [.entries[] | select(.type=="breadcrumbs") | .data.values[]] | .[-10:][] |
  "\(.timestamp) [\(.category // .type)] \(.level // "-"): \(.message // ((.data // {}) | tostring))"
' "$EVENT_JSON"

echo ""
echo "--- extra context keys ---"
jq -r '(.context // {}) | keys | join(", ")' "$EVENT_JSON"

echo ""
echo "Full JSON: $ISSUE_JSON and $EVENT_JSON (query with jq for more detail)"
