#!/bin/bash
# restore_husky_hooks <worktree-top> <hooks-path>
# The sandbox keeps .husky read-only, so a sandboxed install cannot create
# .husky/_ in a new worktree, and git then skips every repo hook. Hooks run
# outside the sandbox, so this copies the directory from the main worktree,
# which the same rule protects. Only husky's own path is copied: .git/config
# is writable, so any other value could make the copy read a denied path.
restore_husky_hooks() {
  local top="$1" hooks_path="${2%/}" dest main
  [ "$hooks_path" = ".husky/_" ] || return 0
  dest="$top/$hooks_path"
  [ -d "$dest" ] && return 0
  main=$(git -C "$top" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
  [ -n "$main" ] && [ "$main" != "$top" ] && [ -d "$main/$hooks_path" ] || return 0
  mkdir -p "$(dirname "$dest")" && cp -R "$main/$hooks_path" "$dest" 2>/dev/null || rm -rf "$dest"
}
