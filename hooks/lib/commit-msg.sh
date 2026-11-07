#!/bin/bash
# Shared commit message extraction for the `git commit` hooks.
#
# The conventional-commit gate checks the subject and the prose gate lints the
# whole message, so both read it through this one parse.

# commit_reuses_message <command>
# Succeeds for amend, fixup, squash and reuse commits, whose message git
# generates or copies, so it is not ours to police.
commit_reuses_message() {
  printf '%s\n' "$1" | grep -qE -- '(--amend|--fixup=|--squash=|--no-edit|-C[[:space:]]+|--reuse-message=)'
}

# extract_commit_msg <command>
# Prints the heredoc message, or every -m / --message value, or nothing.
extract_commit_msg() {
  printf '%s' "$1" | python3 -c '
import sys, re

cmd = sys.stdin.read()

# Only a heredoc opened after `git commit` can carry its message. A command
# chain may open others first, such as a PR body written to a file, and
# reading those attributes unrelated prose to this change.
anchor = cmd.find("git commit")
scope = cmd[anchor:] if anchor != -1 else cmd

m = re.search(r"<<-?[\x27\"]?(\w+)[\x27\"]?", scope)
if m:
    delim = m.group(1)
    after = scope[m.end():]
    nl = after.find("\n")
    if nl != -1:
        out = []
        for line in after[nl + 1:].split("\n"):
            if line.strip() == delim:
                break
            out.append(line)
        print("\n".join(out))
        sys.exit(0)

# The backreference keeps a quote of the other kind inside the message from
# ending the match early.
vals = [m.group(2) for m in
        re.finditer(r"(?:-m|--message)[=\s]+([\x27\"])(.*?)\1", scope, re.S)]
if vals:
    print("\n".join(vals))
' 2>/dev/null
}
