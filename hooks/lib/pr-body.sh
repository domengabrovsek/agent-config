#!/bin/bash
# Shared PR body extraction for the `gh pr` hooks.
#
# Two hooks read the same body out of one command string: the prose gate lints
# its wording, the body gate checks it against rules/git-conventions.md. A copy
# each is how lib/resolve-repo.sh came to exist, so the parse lives here once.
#
# Handles the three shapes gh accepts: `--body-file <path>`, a `--body`
# heredoc, and a quoted `--body` / `-b` value. A command with no body prints
# nothing, which every caller already treats as "nothing to check".

# pr_body_file <command>
# Prints the --body-file path, or nothing when the command uses no such flag.
pr_body_file() {
  printf '%s' "$1" | python3 -c '
import sys, re
cmd = sys.stdin.read()
m = re.search(r"--body-file[=\s]+[\x27\"]?([^\x27\"\s]+)", cmd)
print(m.group(1) if m else "")
' 2>/dev/null
}

# extract_pr_body <command>
# Prints the body text the command would send.
extract_pr_body() {
  local command="$1" body_file

  body_file=$(pr_body_file "$command")
  if [ -n "$body_file" ] && [ -f "$body_file" ]; then
    cat "$body_file"
    return 0
  fi

  printf '%s' "$command" | python3 -c '
import sys, re

cmd = sys.stdin.read()

# A heredoc body ends at its delimiter, not at the end of the command, so a
# later flag on the same line never gets read as prose.
m = re.search(r"--body[=\s]+<<-?[\x27\"]?(\w+)[\x27\"]?", cmd)
if m:
    delim = m.group(1)
    after = cmd[m.end():]
    nl = after.find("\n")
    if nl != -1:
        out = []
        for line in after[nl + 1:].split("\n"):
            if line.strip() == delim:
                break
            out.append(line)
        print("\n".join(out))
        sys.exit(0)

# The backreference keeps a quote of the other kind inside the body from
# ending the match early.
vals = [m.group(2) for m in
        re.finditer(r"(?:-b|--body)[=\s]+([\x27\"])(.*?)\1", cmd, re.S)]
if vals:
    print("\n".join(vals))
' 2>/dev/null
}
