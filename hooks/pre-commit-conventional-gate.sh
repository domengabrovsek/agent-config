#!/bin/bash
# Pre-commit conventional-commit format gate.
# PreToolUse hook on Bash(git commit *). Extracts the subject line from the
# commit command and checks it against the conventional-commits regex from
# rules/git-conventions.md.
#
# Skips amend / fixup / squash / no-edit (auto-generated messages or reusing
# existing) and Merge / Revert subjects (git auto-generated).
#
# Bypass with SKIP_CONVENTIONAL_GATE=1.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

case "$COMMAND" in
  *"git commit --help"*|*"git commit -h"*) exit 0 ;;
  *"git commit"*) ;;
  *) exit 0 ;;
esac

[ "$SKIP_CONVENTIONAL_GATE" = "1" ] && exit 0

# Auto-generated message paths - skip.
if echo "$COMMAND" | grep -qE -- '(--amend|--fixup=|--squash=|--no-edit|-C[[:space:]]+|--reuse-message=)'; then
  exit 0
fi

SUBJECT=$(printf '%s' "$COMMAND" | python3 -c '
import sys, re

cmd = sys.stdin.read()

# Only a heredoc opened after `git commit` can carry its message. A command
# chain may open others first, such as a PR body written to a file, and
# reading those attributes unrelated prose to this change.
anchor = cmd.find("git commit")
scope = cmd[anchor:] if anchor != -1 else cmd

# Prefer heredoc when the command uses one - it carries the structured message.
heredoc_re = re.compile(r"<<-?[\047\"]?(\w+)[\047\"]?")
m = heredoc_re.search(scope)
if m:
    delim = m.group(1)
    after = scope[m.end():]
    # Drop everything up to and including the first newline after the opener.
    nl = after.find("\n")
    if nl != -1:
        body = after[nl + 1:]
        for line in body.split("\n"):
            stripped = line.strip()
            if not stripped:
                continue
            if stripped == delim:
                break
            print(stripped)
            sys.exit(0)

# Fall back to the first -m / --message value.
m_re = re.search(r"(?:-m|--message)[=\s]+[\047\"]([^\047\"]+)[\047\"]", scope)
if m_re:
    print(m_re.group(1).splitlines()[0])
    sys.exit(0)
' 2>/dev/null)

# Could not extract a subject - let it through; not our concern to second-guess.
[ -z "$SUBJECT" ] && exit 0

# Git auto-generates Merge / Revert subjects on certain operations.
case "$SUBJECT" in
  "Merge "*|"Revert "*) exit 0 ;;
esac

if ! echo "$SUBJECT" | grep -qE '^(feat|fix|refactor|docs|chore|test|ci|perf|build|style|revert)(\([^)]+\))?!?: .+'; then
  echo "[pre-commit-conventional-gate] Commit subject does not match the conventional-commits format." >&2
  echo "Subject: $SUBJECT" >&2
  echo "Expected: <type>(<scope>)?!?: <description>" >&2
  echo "Allowed types: feat|fix|refactor|docs|chore|test|ci|perf|build|style|revert" >&2
  echo "Per rules/git-conventions.md." >&2
  echo "(Bypass: SKIP_CONVENTIONAL_GATE=1)" >&2
  exit 2
fi

exit 0
