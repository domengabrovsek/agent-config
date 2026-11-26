#!/bin/bash
# Excluded-command gate.
# Claude Code runs a command outside the sandbox only when the whole call
# matches an excludedCommands entry in settings.json. A redirect, pipe, `cd`,
# chain, or command substitution keeps the call sandboxed, and the script
# then fails on a sandbox write deny. This gate blocks such a call to the two
# excluded scripts and prints the exact form, so the agent retries it alone.
# PreToolUse hook for Bash. Exit 2 blocks the action and feeds the message
# back to Claude as a tool result.
# Bypass with SKIP_EXCLUDED_COMMAND_GATE=1 in the environment.

# The tildes below are literal command text, never expanded.
# shellcheck disable=SC2088

# shellcheck source=lib/hook.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/hook.sh"

hook_read
case "$COMMAND" in
  *gcloud-agent-login.sh*|*worktree-fill-protected.sh*) ;;
  *) exit 0 ;;
esac
hook_bypass SKIP_EXCLUDED_COMMAND_GATE && exit 0

SCRIPT_RE='(~|\$HOME|\$\{HOME\}|/[^[:space:]]*)/\.agents/scripts/(gcloud-agent-login|worktree-fill-protected)\.sh'
# Only an invocation counts: the script path in command position, alone or
# after an operator, an opening paren, or a shell wrapper. Reading the file
# with sed or cat passes.
INVOKE_RE="(^|[;&|({]|\\\$\\(|\`)[[:space:]]*((bash|sh|exec|command|env)[[:space:]]+)?$SCRIPT_RE"
printf '%s\n' "$COMMAND" | grep -Eq "$INVOKE_RE" || exit 0

EXACT_GCLOUD='~/.agents/scripts/gcloud-agent-login.sh nonprod'
FILL_RE='^~/\.agents/scripts/worktree-fill-protected\.sh [A-Za-z0-9._/@+-]+$'
[ "$COMMAND" = "$EXACT_GCLOUD" ] && exit 0
printf '%s' "$COMMAND" | grep -Eq "$FILL_RE" && [ "$(printf '%s' "$COMMAND" | wc -l | tr -d ' ')" = 0 ] && exit 0

case "$COMMAND" in
  *gcloud-agent-login.sh*)
    hook_block pre-excluded-command-gate SKIP_EXCLUDED_COMMAND_GATE \
      "This call stays in the sandbox, so the token refresh would fail on a write deny." \
      "Only this exact text leaves the sandbox. Run it alone, with no redirect, pipe, cd, or chain:" \
      "  $EXACT_GCLOUD" \
      "Never refresh production; ask the user." ;;
  *)
    hook_block pre-excluded-command-gate SKIP_EXCLUDED_COMMAND_GATE \
      "This call stays in the sandbox, so the protected files cannot be written." \
      "Run it alone, spelled with ~ and one plain worktree path, with no redirect, pipe, cd, or chain:" \
      "  ~/.agents/scripts/worktree-fill-protected.sh <main-checkout>/.claude/worktrees/<slug>" ;;
esac
