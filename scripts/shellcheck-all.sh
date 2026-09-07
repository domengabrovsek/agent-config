#!/bin/bash
# Run shellcheck over every tracked shell script.
#
# Files are discovered by extension or shebang rather than listed, so a new
# hook or skill script is covered the day it lands. Severity is "warning":
# style nits stay advisory, real defects fail the build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# GitHub's ubuntu images ship shellcheck; install only where it is absent.
if ! command -v shellcheck >/dev/null 2>&1; then
  SUDO=""
  [ "$(id -u)" -eq 0 ] || SUDO="sudo"
  if command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get update -qq && $SUDO apt-get install -y -qq shellcheck
  elif command -v brew >/dev/null 2>&1; then
    brew install shellcheck
  else
    echo "shellcheck is not installed and no known package manager is available." >&2
    exit 1
  fi
fi

FILES=()
while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$f" in
    *.sh) FILES+=("$f"); continue ;;
  esac
  # No extension: fall back to the shebang.
  if head -1 "$f" | grep -qE '^#!.*(/|env +)(ba)?sh\b'; then
    FILES+=("$f")
  fi
done < <(git ls-files)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "No shell scripts found." >&2
  exit 1
fi

echo "Checking ${#FILES[@]} shell script(s) with $(shellcheck --version | awk '/^version:/ {print $2}')."
printf '  %s\n' "${FILES[@]}"
echo

shellcheck --severity=warning --format=gcc "${FILES[@]}"
echo "OK: no shellcheck findings at warning severity or above."
