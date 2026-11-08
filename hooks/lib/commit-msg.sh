#!/bin/bash
# Shared commit message handling for the `git commit` hooks and the PR title.
#
# The conventional-commit gate checks the subject and the prose gate lints the
# whole message, so both read it through this one parse. The PR test gate
# checks titles against the same types, which the CI title check
# (amannn/action-semantic-pull-request) accepts by default.

# shellcheck source=resolve-repo.sh
. "$(dirname "${BASH_SOURCE[0]}")/resolve-repo.sh"

CONVENTIONAL_TYPES="feat|fix|refactor|docs|chore|test|ci|perf|build|style|revert"

# is_conventional <subject>
# Succeeds when the subject reads `<type>(<scope>)?!?: <description>`.
is_conventional() {
  printf '%s\n' "$1" | grep -qE "^(${CONVENTIONAL_TYPES})(\([^)]+\))?!?: .+"
}

# commit_reuses_message <command>
# Succeeds for amend, fixup, squash and reuse commits, whose message git
# generates or copies, so it is not ours to police. Only the commit's own
# arguments count: a `git -C` elsewhere in the chain is not `commit -C`.
commit_reuses_message() {
  local arg
  parse_git_command "$1" "" commit || return 1
  for arg in ${GIT_ARGS[@]+"${GIT_ARGS[@]}"}; do
    case "$arg" in
      --amend|--fixup|--fixup=*|--squash|--squash=*|--no-edit|-C|-C?*|--reuse-message|--reuse-message=*) return 0 ;;
    esac
  done
  return 1
}

# extract_commit_msg <command>
# Prints the heredoc message, or every -m / --message value, or nothing.
extract_commit_msg() {
  printf '%s' "$1" | python3 -c '
import sys, re

cmd = sys.stdin.read()

# Only a heredoc opened after the commit call can carry its message. A command
# chain may open others first, such as a PR body written to a file, and
# reading those attributes unrelated prose to this change. Global options may
# sit between git and commit.
call = re.search(
    r"\bgit(?:\s+(?:-[Cc]\s+(?:\"[^\"]*\"|\x27[^\x27]*\x27|\S+)"
    r"|--(?:git-dir|work-tree|namespace|exec-path|config-env)\s+\S+|-\S+))*\s+commit\b",
    cmd)
scope = cmd[call.end():] if call else cmd

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
