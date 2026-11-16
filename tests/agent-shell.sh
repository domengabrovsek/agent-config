#!/bin/bash
# Tests for hooks/lib/agent-shell.sh, the CLAUDE_ENV_FILE preamble.
#
# After a cd, node comes from the nearest .nvmrc, a partial version picks the
# newest installed match, and an alias or a missing version leaves PATH alone.
# The rm/mv/cp aliases are gone in both zsh and bash.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
PREAMBLE="$PROJECT_DIR/hooks/lib/agent-shell.sh"
harness_init agent-shell

NVM="$TEST_ROOT/nvm"
for v in 24.22.3 26.9.0 26.13.1; do
  mkdir -p "$NVM/versions/node/v$v/bin"
  printf '#!/bin/sh\necho v%s\n' "$v" > "$NVM/versions/node/v$v/bin/node"
  chmod +x "$NVM/versions/node/v$v/bin/node"
done
mkdir -p "$TEST_ROOT/exact/sub" "$TEST_ROOT/partial" "$TEST_ROOT/alias" "$TEST_ROOT/missing"
echo "v26.13.1" > "$TEST_ROOT/exact/.nvmrc"
echo "26" > "$TEST_ROOT/partial/.nvmrc"
echo "lts/*" > "$TEST_ROOT/alias/.nvmrc"
echo "30.0.0" > "$TEST_ROOT/missing/.nvmrc"

# no_rc <shell>: the flag that skips startup files, which may reset NVM_DIR.
no_rc() { if [ "$1" = zsh ]; then echo -f; else echo --norc; fi; }

# node_after <shell> <dir>: the node version after sourcing the preamble and cd.
node_after() {
  NVM_DIR="$NVM" PATH="$NVM/versions/node/v24.22.3/bin:/usr/bin:/bin" "$1" $(no_rc "$1") -c \
    ". '$PREAMBLE'; cd '$2' && node"
}

for sh in bash zsh; do
  command -v "$sh" > /dev/null || continue
  echo "== $sh =="
  check_eq() {
    if [ "$2" = "$3" ]; then pass "$sh: $1"; else echo "    want $3, got $2" >&2; fail "$sh: $1"; fi
  }
  check_eq "an exact .nvmrc picks that version" "$(node_after "$sh" "$TEST_ROOT/exact")" v26.13.1
  check_eq "a subdirectory finds the parent .nvmrc" "$(node_after "$sh" "$TEST_ROOT/exact/sub")" v26.13.1
  check_eq "a partial version picks the newest match" "$(node_after "$sh" "$TEST_ROOT/partial")" v26.13.1
  check_eq "an alias leaves PATH alone" "$(node_after "$sh" "$TEST_ROOT/alias")" v24.22.3
  check_eq "a missing version leaves PATH alone" "$(node_after "$sh" "$TEST_ROOT/missing")" v24.22.3
  got=$("$sh" -c "alias rm='rm -i' 2>/dev/null; . '$PREAMBLE'; alias rm 2>/dev/null || echo none")
  check_eq "the rm alias is removed" "$got" none
done

finish
