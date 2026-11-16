#!/bin/bash
# Shared per-call dedup for the Bash hooks that settings.json registers under
# several `if` rules.
#
# An `if` takes one pattern, so a hook that guards several commands needs one
# registration per command. Claude Code runs every registration that matches,
# and a chain such as `git commit && git push`, or any command holding $() or
# $VAR, matches several, so the same hook gets the same payload more than once
# in parallel. Those runs reach the same verdict, so the first one to claim the
# tool call does the work and the others exit 0. A block from the first run
# still blocks the call. Registrations of one hook share one timeout, so the
# run that does the work is never the one killed sooner.
#
# Bash payloads only: the Codex dispatcher splits one apply_patch into several
# Edit calls that share a tool_use_id.

# first_run_for_call <payload> <key>
# Succeeds for the first run of <key> on this tool call, and whenever the
# payload has no usable tool_use_id or the claim cannot be written. Fails for
# every later run.
#
# A claim written by another user would skip a gate, so the claim dir must be
# a real dir owned by the current user. When a shared TMPDIR such as /tmp
# already holds one owned by someone else, the claims move to a per-user dir.
first_run_for_call() {
  local id event dir claim
  # A literal key inside a JSON string value is escaped as \"tool_use_id\",
  # which this pattern never matches.
  [[ $1 =~ \"tool_use_id\":\ *\"([A-Za-z0-9_-]+)\" ]] || return 0
  id=${BASH_REMATCH[1]}
  event=""
  [[ $1 =~ \"hook_event_name\":\ *\"([A-Za-z]+)\" ]] && event=${BASH_REMATCH[1]}
  dir="${TMPDIR:-/tmp}"
  dir="${dir%/}/agent-hook-once"
  mkdir -m 700 "$dir" 2>/dev/null
  if [ -L "$dir" ] || [ ! -O "$dir" ]; then
    dir="$dir-${EUID:-$(id -u)}"
    mkdir -m 700 "$dir" 2>/dev/null
    { [ ! -L "$dir" ] && [ -O "$dir" ]; } || return 0
  fi
  claim="$dir/$id.$event.$2"
  if mkdir "$claim" 2>/dev/null; then
    find "$dir" -mindepth 1 -maxdepth 1 -type d -mmin +1440 -delete 2>/dev/null
    return 0
  fi
  [ -d "$claim" ] && return 1
  return 0
}
