#!/bin/bash
# Shared AI attribution checks, per rules/git-conventions.md.
#
# The commit message gate and the PR body gate ban the same attribution, so
# both read the patterns from here. Each gate picks the checks it enforces.

# attribution_problems <text> [check...]
# Prints one line per banned attribution found in <text>. The checks are
# coauthor (a Co-Authored-By trailer), footer (a "Generated with" footer) and
# robot (the robot emoji that marks the footer). No check named runs all three.
attribution_problems() {
  local text="$1" check
  shift
  [ $# -gt 0 ] || set -- coauthor footer robot
  for check in "$@"; do
    case "$check" in
      coauthor)
        printf '%s' "$text" | grep -qiE '\bco-authored-by:' \
          && echo "Co-Authored-By trailer. rules/git-conventions.md bans AI attribution."
        ;;
      footer)
        printf '%s' "$text" | grep -qiE 'generated with.{0,40}(claude|codex|copilot|chatgpt)' \
          && echo "A \"Generated with\" footer. rules/git-conventions.md bans AI attribution."
        ;;
      robot)
        printf '%s' "$text" | grep -q '🤖' \
          && echo "A robot emoji. It marks the attribution footer the same rule bans."
        ;;
    esac
  done
  return 0
}
