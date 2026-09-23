#!/bin/bash
# Send a macOS desktop notification unless a terminal emulator or IDE is in the foreground.
# Usage: ~/.agents/scripts/notify.sh "your message here"

MSG="${1:-Agent needs your input}"

# Apps where the user is likely already seeing agent output
FOREGROUND_APPS="wezterm-gui|Ghostty|iTerm2|Alacritty|kitty|Terminal|Code|Cursor"

FRONT_APP=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)

if echo "$FRONT_APP" | grep -qE "$FOREGROUND_APPS"; then
  exit 0
fi

osascript -e "display notification \"$MSG\" with title \"Agent\" sound name \"default\""
