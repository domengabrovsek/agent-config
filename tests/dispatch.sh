#!/bin/bash
# Tests for hooks/lib/dispatch.sh against a throwaway registry and stub hooks.
# Each stub appends its name and the payload it saw to a log, so a test can
# assert which hooks ran, in what order, and with which normalized input.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
DISPATCH="$PROJECT_DIR/hooks/lib/dispatch.sh"

harness_init dispatch TEST_DIR

STUBS="$TEST_DIR/stubs"
LOG="$TEST_DIR/log"
WORK="$TEST_DIR/work"
mkdir -p "$WORK"

# hook <name> <exit> [stdout] [stderr]: a stub hook that logs what it saw.
hook() {
  stub "$STUBS" "$1" <<STUB
#!/bin/bash
printf '%s %s\n' "$1" "\$(jq -c '{t: .tool_name, c: .tool_input.command, f: .tool_input.file_path}')" >> "$LOG"
printf '%s' '${3:-}'
printf '%s' '${4:-}' >&2
exit $2
STUB
}

hook push 0
hook commit 0
hook edit 0
hook post 0
hook blocker 2 "" "blocked by stub"
hook broken 1
hook ctx-a 0 '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"alpha"}}'
hook ctx-b 0 '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"beta"}}'
hook slow 0

REGISTRY="$TEST_DIR/settings.json"
S="$STUBS"
cat > "$REGISTRY" <<JSON
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "$S/push", "if": "Bash(git push *)" },
          { "type": "command", "command": "$S/commit", "if": "Bash(git commit *)" },
          { "type": "command", "command": "$S/broken", "if": "Bash(gh pr create *)" },
          { "type": "command", "command": "$S/blocker", "if": "Bash(gh pr create *)" },
          { "type": "command", "command": "$S/push", "if": "Bash(gh pr create *)" },
          { "type": "command", "command": "$S/ctx-a", "if": "Bash(gh api *)" },
          { "type": "command", "command": "$S/ctx-b", "if": "Bash(gh api *)" },
          { "type": "command", "command": "sleep 5; $S/slow", "if": "Bash(sleep-test *)", "timeout": 1 },
          { "type": "command", "command": "$S/commit", "if": "Bash(git -C *)" }
        ]
      },
      {
        "matcher": "Write|Edit",
        "hooks": [ { "type": "command", "command": "$S/edit" } ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [ { "type": "command", "command": "$S/post" } ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [ { "type": "command", "command": "echo \"hooks at \$HOME/.claude/hooks/\"" } ]
      },
      {
        "matcher": "compact",
        "hooks": [ { "type": "command", "command": "echo compacted" } ]
      }
    ]
  }
}
JSON

OUT="$TEST_DIR/out"
ERR="$TEST_DIR/err"

# dispatch <event> <json-payload>; sets RC
dispatch() {
  : > "$LOG"
  printf '%s' "$2" | HOOK_REGISTRY="$REGISTRY" bash "$DISPATCH" "$1" > "$OUT" 2> "$ERR"
  RC=$?
}

bash_call() {
  CMD="$1" CWD="$WORK" TOOL="${2:-Bash}" python3 -c 'import json,os; print(json.dumps({"tool_name":os.environ["TOOL"],"tool_input":{"command":os.environ["CMD"]},"cwd":os.environ["CWD"]}))'
}

# eq <got> <want> <name>
eq() {
  if [ "$1" = "$2" ]; then pass "$3"; else
    echo "    want: $2" >&2
    echo "    got:  $1" >&2
    fail "$3"
  fi
}

ran() { awk '{print $1}' "$LOG" | tr '\n' ' ' | sed 's/ $//'; }

dispatch PreToolUse "$(bash_call "git push origin feat/x")"
eq "$RC $(ran)" "0 push" "if glob matches the command"

dispatch PreToolUse "$(bash_call "git pull")"
eq "$RC $(ran)" "0 " "if glob that does not match runs nothing"

dispatch PreToolUse "$(bash_call "git push")"
eq "$(ran)" "push" "a trailing space-star also matches the bare command"

dispatch PreToolUse "$(bash_call "cd /tmp && npm test; git commit -m 'feat: x' | cat")"
eq "$(ran)" "commit" "a segment of a compound command matches"

dispatch PreToolUse "$(bash_call "git -C . status && git commit -m x")"
eq "$(ran)" "commit" "a hook matched by two if rules runs once per call"

dispatch PreToolUse "$(bash_call "git push origin x" exec_command)"
eq "$(ran)" "push" "exec_command normalizes to Bash"

dispatch PreToolUse "$(printf '{"tool_name":"shell","tool_input":{"command":["bash","-lc","git push"]},"cwd":"%s"}' "$WORK")"
eq "$(ran)" "push" "an argv command list uses the script argument"

dispatch PreToolUse "$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/a.ts"},"cwd":"%s"}' "$WORK" "$WORK")"
eq "$(ran)" "edit" "matcher Write|Edit selects Write"

dispatch PreToolUse "$(printf '{"tool_name":"edit","tool_input":{"path":"src/b.ts"},"cwd":"%s"}' "$WORK")"
eq "$(sed -n 1p "$LOG")" "edit {\"t\":\"Edit\",\"c\":null,\"f\":\"$WORK/src/b.ts\"}" "a lowercase edit with a relative path normalizes"

PATCH='*** Begin Patch
*** Add File: new.ts
+x
*** Update File: src/old.ts
*** Move to: src/moved.ts
@@
-a
+b
*** Delete File: gone.ts
*** End Patch'
dispatch PostToolUse "$(bash_call "$PATCH" apply_patch)"
eq "$(awk '{print $2}' "$LOG" | jq -r .f | tr '\n' ' ')" "$WORK/new.ts $WORK/src/old.ts $WORK/src/moved.ts " "apply_patch splits into one Edit per path, deletes skipped"
eq "$(awk '{print $2}' "$LOG" | jq -r .t | sort -u)" "Edit" "apply_patch calls are Edit calls"

dispatch PreToolUse "$(bash_call "gh pr create --title t")"
eq "$RC $(ran)" "2 broken blocker" "exit 2 blocks and stops later hooks, a non-2 failure does not"
eq "$(cat "$ERR")" "blocked by stub" "the blocking hook's stderr is forwarded"

dispatch PreToolUse "$(bash_call "gh api repos/x")"
eq "$RC $(jq -c . "$OUT")" '0 {"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"alpha\n\nbeta"}}' "additionalContext from several hooks is merged"

START=$(date +%s)
dispatch PreToolUse "$(bash_call "sleep-test now")"
ELAPSED=$(( $(date +%s) - START ))
eq "$RC $(ran) $([ "$ELAPSED" -lt 4 ] && echo fast)" "0  fast" "a hook past its timeout is killed and ignored"

dispatch SessionStart "$(printf '{"source":"compact","cwd":"%s"}' "$WORK")"
eq "$(jq -r .hookSpecificOutput.additionalContext "$OUT")" "compacted" "SessionStart matcher selects by source and plain stdout becomes context"

dispatch SessionStart "$(printf '{"source":"startup","cwd":"%s"}' "$WORK")"
eq "$(jq -r .hookSpecificOutput.additionalContext "$OUT")" "hooks at $PROJECT_DIR/hooks/" "the ~/.claude/hooks fallback resolves to the dispatcher's repo"

dispatch Stop "$(printf '{"cwd":"%s"}' "$WORK")"
eq "$RC $(cat "$OUT")$(ran)" "0 " "an event missing from the registry is a no-op"

dispatch PreToolUse "not json"
eq "$RC" "0" "a malformed payload is a no-op"

HOST_LOG="$TEST_DIR/host.log"
HOST_REGISTRY="$TEST_DIR/host-registry.json"
printf '#!/bin/bash\ncat >/dev/null\nprintf "%%s\\n" "${AGENT_HOOK_HOST:-unset}" >> "%s"\n' "$HOST_LOG" > "$STUBS/host"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash %s"}]}]}}' "$STUBS/host" > "$HOST_REGISTRY"
bash_call "ls" | HOOK_REGISTRY="$HOST_REGISTRY" bash "$DISPATCH" PreToolUse >/dev/null 2>&1
bash_call "ls" | AGENT_HOOK_HOST=pi HOOK_REGISTRY="$HOST_REGISTRY" bash "$DISPATCH" PreToolUse >/dev/null 2>&1
eq "$(tr '\n' ' ' < "$HOST_LOG")" "codex pi " "hooks see codex by default and the caller's host when set"

finish
