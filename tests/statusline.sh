#!/bin/bash
# Tests for scripts/statusline.sh. Each run uses an empty config dir and a
# non-git cwd, so the credits block and the git block stay out of the output.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
SCRIPT="$PROJECT_DIR/scripts/statusline.sh"
harness_init statusline TEST_DIR

# render <json>: sets OUT to the status line with ANSI codes stripped
render() {
  OUT=$(printf '%s' "$1" | CLAUDE_CONFIG_DIR="$TEST_DIR" sh "$SCRIPT" | sed 's/\x1b\[[0-9;]*m//g')
}
diagnose() { echo "    output: $OUT"; }

render "{\"cwd\":\"$TEST_DIR\",\"model\":{\"display_name\":\"Opus 5.5\"},\"effort\":{\"level\":\"high\"}}"
check "shows the model and its effort" says "Opus 5.5 high"

render "{\"cwd\":\"$TEST_DIR\",\"model\":{\"display_name\":\"Haiku 4.5\"}}"
check "shows the model without effort when effort is absent" says "Haiku 4.5"
check "omits the effort when it is absent" says "Haiku 4.5 │"

render "{\"cwd\":\"$TEST_DIR\"}"
check "omits the model block when no model is sent" omits "null"

finish
