#!/bin/bash
# Send a macOS desktop notification unless a terminal emulator or IDE is in
# the foreground, where the user likely already sees the agent output.
#
# Usage: ~/.agents/scripts/notify.sh ["message"] [--help]
#
# The message defaults to "Agent needs your input". AppleScript receives it
# as an argument, so quotes and backslashes show up as typed.

set -u

case "${1:-}" in
  -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

MSG="${1:-Agent needs your input}"

FOREGROUND_APPS="wezterm-gui|Ghostty|iTerm2|Alacritty|kitty|Terminal|Code|Cursor"

FRONT_APP=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)

if echo "$FRONT_APP" | grep -qE "$FOREGROUND_APPS"; then
  exit 0
fi

osascript -e 'on run argv' \
  -e 'display notification (item 1 of argv) with title "Agent" sound name "default"' \
  -e 'end run' "$MSG"
