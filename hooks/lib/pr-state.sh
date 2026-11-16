#!/bin/bash
# Shared PR lookup for the hooks that run on a `git push`.
#
# pre-git-state-refresh.sh and pre-push-gate.sh both ask gh for the branch's
# PR on the same push, and Claude Code runs them in parallel. The first one to
# ask runs `gh pr view` and leaves the answer in its once.sh claim dir. The
# other waits for that answer, so one push makes one network call.

# shellcheck source=once.sh
. "$(dirname "${BASH_SOURCE[0]}")/once.sh"

# pr_state <payload> <dir>
# Prints the JSON of `gh pr view --json state,mergedAt,headRefName,url` for
# the branch checked out in <dir>, or nothing when it has no PR or gh fails.
# A run that finds the lookup already claimed waits up to 10 seconds for the
# answer, then asks gh itself, so a killed first run never blocks it.
pr_state() {
  local key json i
  key="pr-state-$(printf '%s' "$2" | cksum | cut -d' ' -f1)"
  if first_run_for_call "$1" "$key"; then
    json=$(_pr_state_fetch "$2")
    if [ -n "$ONCE_CLAIM" ]; then
      # The claim dir is only removed once empty, so stale answers go first.
      find "${ONCE_CLAIM%/*}" -mindepth 2 -maxdepth 2 -name answer -mmin +1440 -delete 2>/dev/null
      printf '%s' "$json" > "$ONCE_CLAIM/answer.$$" 2>/dev/null \
        && mv -f "$ONCE_CLAIM/answer.$$" "$ONCE_CLAIM/answer" 2>/dev/null
    fi
    printf '%s\n' "$json"
    return 0
  fi
  for ((i = 0; i < 50; i++)); do
    if [ -f "$ONCE_CLAIM/answer" ]; then
      cat "$ONCE_CLAIM/answer"
      return 0
    fi
    sleep 0.2
  done
  _pr_state_fetch "$2"
}

# gh has no -C and reads the branch from its cwd, so it runs from <dir>.
_pr_state_fetch() {
  (cd "$1" 2>/dev/null && gh pr view --json state,mergedAt,headRefName,url 2>/dev/null)
}
