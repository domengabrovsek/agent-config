#!/bin/bash
# Shared hook output for the hooks that inject context instead of blocking.

# emit_context <event> <text>
# Prints the hook JSON that adds <text> to the model's context.
emit_context() {
  jq -n --arg event "$1" --arg ctx "$2" '{
  continue: true,
  hookSpecificOutput: {
    hookEventName: $event,
    additionalContext: $ctx
  }
}'
}
