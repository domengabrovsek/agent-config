#!/bin/bash
# Tests for hooks/pre-excluded-command-gate.sh: only the exact excluded forms
# of the two sandbox-excluded scripts pass. Every other call to them blocks,
# and unrelated commands or reads of the scripts pass.

# The commands under test are literal text, so their tildes stay quoted.
# shellcheck disable=SC2088

set -uo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
harness_init excluded-command-gate
HOOK="$PROJECT_DIR/hooks/pre-excluded-command-gate.sh"
OUT=""
STATUS=0

# shellcheck disable=SC2034  # the harness's says reads OUT
run_gate() {
  OUT=$(payload "$1" | bash "$HOOK" 2>&1)
  STATUS=$?
}

passes() {
  run_gate "$2"
  check "$1" [ "$STATUS" -eq 0 ]
}

blocks() {
  run_gate "$2"
  check "$1" [ "$STATUS" -eq 2 ]
}

WT=/Users/u/dev/repo/.claude/worktrees/slug

passes "the exact gcloud refresh passes" '~/.agents/scripts/gcloud-agent-login.sh nonprod'
passes "the fill script with one plain path passes" "~/.agents/scripts/worktree-fill-protected.sh $WT"
passes "reading the script passes" 'sed -n 1,40p ~/.agents/scripts/gcloud-agent-login.sh'
passes "the test suite passes" 'bash tests/gcloud-agent-login.sh 2>&1 | tail -3'
passes "git add of the script passes" 'git add scripts/worktree-fill-protected.sh'
passes "an unrelated command passes" 'ls -la'

blocks "a piped refresh blocks" '~/.agents/scripts/gcloud-agent-login.sh nonprod 2>&1 | tail -5'
check "the block prints the exact form" says "  ~/.agents/scripts/gcloud-agent-login.sh nonprod"
check "the block names the bypass" says "SKIP_EXCLUDED_COMMAND_GATE"
blocks "a refresh after cd blocks" 'cd /tmp && ~/.agents/scripts/gcloud-agent-login.sh nonprod'
blocks "a chained refresh blocks" '~/.agents/scripts/gcloud-agent-login.sh nonprod; echo done'
blocks "an absolute script path blocks" '/Users/u/.agents/scripts/gcloud-agent-login.sh nonprod'
blocks "a \$HOME script path blocks" '$HOME/.agents/scripts/gcloud-agent-login.sh nonprod'
blocks "a bash-wrapped refresh blocks" 'bash ~/.agents/scripts/gcloud-agent-login.sh nonprod'
blocks "a production refresh blocks" '~/.agents/scripts/gcloud-agent-login.sh production'
check "the production block says to ask the user" says "Never refresh production"
blocks "a fill with a redirect blocks" "~/.agents/scripts/worktree-fill-protected.sh $WT 2>&1"
blocks "a fill with a substitution blocks" '~/.agents/scripts/worktree-fill-protected.sh "$(pwd)"'
blocks "a fill with two arguments blocks" "~/.agents/scripts/worktree-fill-protected.sh $WT extra"
blocks "a fill with a trailing newline command blocks" "$(printf '%s\n%s' "~/.agents/scripts/worktree-fill-protected.sh $WT" 'touch ~/x')"

payload '~/.agents/scripts/gcloud-agent-login.sh nonprod | tail' | SKIP_EXCLUDED_COMMAND_GATE=1 bash "$HOOK" >/dev/null 2>&1
STATUS=$?
check "the bypass lets the call through" [ "$STATUS" -eq 0 ]

finish
