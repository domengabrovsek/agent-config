#!/bin/bash
# Tests for the pre-push gate.
#
# A fresh worktree has no .env, and a build that validates its env fails
# there for reasons unrelated to the branch. The gate builds such a checkout
# with the committed .env.example, and leaves a checkout with its own env alone.
#
# A repo that declares `verify:fast` runs only that, and a checkout whose
# core.hooksPath directory is missing blocks until the install creates it.
#
# Node checks run through the repo's package manager. Those cases run the gate
# under a PATH of stub managers, so no real npm, pnpm, or yarn runs.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
harness_init pre-push-gate
STUB_LOG="$TEST_ROOT/stub.log"

diagnose() {
  echo "    exit ${STATUS:-}, got: ${OUT:-}"
  [ -f "$STUB_LOG" ] && echo "    calls: $(paste -sd ';' - < "$STUB_LOG")"
  return 0
}

# The build passes only when GATE_PROBE carries the template's value.
make_project() {
  local dir="$1"
  mkdir -p "$dir/node_modules"
  git -C "$dir" init -q
  cat > "$dir/package.json" <<'JSON'
{
  "name": "probe",
  "private": true,
  "scripts": {
    "build": "node -e \"process.exit(process.env.GATE_PROBE === 'from-template' ? 0 : 1)\""
  }
}
JSON
  printf '# comment\nGATE_PROBE=from-template\n' > "$dir/.env.example"
}

# run_gate <dir> [command]: sets OUT and STATUS for a push from <dir>.
run_gate() {
  OUT=$(payload "${2:-git push origin feature/x}" "$1" \
    | (cd "$TEST_ROOT" && CLAUDE_PROJECT_DIR="" SKIP_PUSH_GATE="" bash "$PROJECT_DIR/hooks/pre-push-gate.sh" 2>&1))
  STATUS=$?
}

FRESH="$TEST_ROOT/fresh"
make_project "$FRESH"
run_gate "$FRESH"
check "a checkout without .env builds with the template" \
  omits "build (env from .env.example) FAILED" says "build (env from .env.example)..."

LOCAL="$TEST_ROOT/local"
make_project "$LOCAL"
printf 'GATE_PROBE=local\n' > "$LOCAL/.env"
run_gate "$LOCAL"
check "a checkout with .env does not load the template" omits ".env.example" says "build FAILED"

HOOKED="$TEST_ROOT/hooked"
make_project "$HOOKED"
printf '#!/bin/sh\nexit 0\n' | stub "$HOOKED/.git/hooks" pre-push
run_gate "$HOOKED"
check "a repo with its own pre-push hook is not gated twice" says "has its own pre-push hook"

run_gate "$HOOKED" "git push --no-verify origin feature/x"
check "--no-verify keeps the gate in force" \
  omits "has its own pre-push hook" says "build (env from .env.example)..."

HUSKY="$TEST_ROOT/husky"
make_project "$HUSKY"
printf '#!/bin/sh\nexit 0\n' | stub "$HUSKY/.husky/_" pre-push
git -C "$HUSKY" config core.hooksPath .husky/_
run_gate "$HUSKY"
check "a husky hooksPath hook counts as the repo's own gate" says "has its own pre-push hook"

NOHOOKS="$TEST_ROOT/nohooks"
make_project "$NOHOOKS"
git -C "$NOHOOKS" config core.hooksPath .husky/_
run_gate "$NOHOOKS"
check "a missing hooksPath directory blocks the push" says "Run 'npm ci'" exited 2

# A global hooksPath is not the repo's own setting, and git expands its ~.
GLOBALHOOKS="$TEST_ROOT/globalhooks"
make_project "$GLOBALHOOKS"
printf '[core]\n\thooksPath = ~/.githooks-missing\n' > "$TEST_ROOT/global.gitconfig"
GIT_CONFIG_GLOBAL="$TEST_ROOT/global.gitconfig" run_gate "$GLOBALHOOKS"
check "a global ~ hooksPath does not block the push" omits "Run 'npm ci'"

# verify:fast fails unless it runs, so a pass proves it ran and nothing else did.
FAST="$TEST_ROOT/fast"
make_project "$FAST"
cat > "$FAST/package.json" <<'JSON'
{
  "name": "probe",
  "private": true,
  "scripts": {
    "verify:fast": "node -e \"require('fs').writeFileSync('ran-fast', '')\"",
    "test": "node -e \"process.exit(1)\""
  }
}
JSON
run_gate "$FAST"
check "a repo declaring verify:fast runs only that" \
  exited 0 omits "[pre-push-gate] test" test -f "$FAST/ran-fast"

cat > "$FAST/package.json" <<'JSON'
{ "name": "probe", "private": true, "scripts": { "verify:fast": "node -e \"process.exit(3)\"" } }
JSON
run_gate "$FAST"
check "a failing verify:fast blocks the push" says "verify:fast FAILED" exited 2

# A stub bun records its arguments, so a pass proves the audit ran through Bun.
BUNREPO="$TEST_ROOT/bunrepo"
make_project "$BUNREPO"
touch "$BUNREPO/bun.lock"
printf '#!/bin/sh\necho "$@" > "%s/bun-args"\n' "$BUNREPO" | stub "$TEST_ROOT/stubbin" bun
PATH="$TEST_ROOT/stubbin:$PATH" run_gate "$BUNREPO"
check "a Bun repo audits with bun audit" \
  exited 0 [ "$(cat "$BUNREPO/bun-args" 2>/dev/null)" = "audit --audit-level=critical" ]

# A PATH holding only the tools the gate needs leaves bun out.
mkdir -p "$TEST_ROOT/nobun"
for tool in bash sh env cat dirname ls grep tail jq git node npm python3; do
  ln -s "$(command -v "$tool")" "$TEST_ROOT/nobun/$tool"
done
PATH="$TEST_ROOT/nobun" run_gate "$BUNREPO"
check "a Bun repo without bun skips the audit" says "audit skipped: bun is not installed" exited 0

echo ""
echo "== merged branch =="

# A stub gh answers `gh pr view` with STUB_PR_STATE, the way -q prints it.
stub "$TEST_ROOT/ghbin" gh <<'STUB'
#!/bin/sh
[ -n "$STUB_PR_STATE" ] || exit 1
echo "$STUB_PR_STATE"
STUB

MERGEDREPO="$TEST_ROOT/mergedrepo"
make_project "$MERGEDREPO"
git -C "$MERGEDREPO" checkout -q -b feature/x

# gate_as <pr-state> <command>: runs the gate in MERGEDREPO with gh reporting <pr-state>.
gate_as() {
  STUB_PR_STATE="$1" PATH="$TEST_ROOT/ghbin:$PATH" run_gate "$MERGEDREPO" "$2"
}
MERGED="MERGED https://github.com/o/r/pull/7"

gate_as "$MERGED" "git push origin feature/x"
check "a push to a merged branch blocks" says "already merged in https://github.com/o/r/pull/7" exited 2

for CMD in "git push origin HEAD" "git push -u origin feature/x" "git push origin HEAD:feature/x" \
  "git push -o ci.skip origin HEAD" "git commit -m 'update push gate docs' && git push origin HEAD" \
  "git -C $MERGEDREPO push origin feature/x"; do
  gate_as "$MERGED" "$CMD"
  check "'$CMD' on a merged branch blocks" exited 2
done

# A delete or a push of another branch is not a push of the merged branch.
for CMD in "git push origin --delete feature/x" "git push origin :feature/x" "git push origin other" \
  "git push origin --tags"; do
  gate_as "$MERGED" "$CMD"
  check "'$CMD' skips the merge check" omits "already merged"
done

gate_as "OPEN https://github.com/o/r/pull/8" "git push origin feature/x"
check "a push to a branch with an open PR passes the merge check" omits "already merged"

gate_as "$MERGED" "SKIP_PUSH_GATE=1 git push origin feature/x"
check "an inline SKIP_PUSH_GATE=1 is not a bypass" exited 2 says "already merged"
check "the merged block never suggests a bypass" omits "SKIP_PUSH_GATE"

OUT=$(payload "git push origin feature/x" "$MERGEDREPO" \
  | (cd "$TEST_ROOT" && CLAUDE_PROJECT_DIR="" SKIP_PUSH_GATE=1 STUB_PR_STATE="$MERGED" PATH="$TEST_ROOT/ghbin:$PATH" \
    bash "$PROJECT_DIR/hooks/pre-push-gate.sh" 2>&1))
STATUS=$?
check "SKIP_PUSH_GATE=1 in the host environment bypasses the gate" exited 0

gate_as "$MERGED" "git -C \"$MERGEDREPO\" -c core.x=y push origin feature/x"
check "a quoted git -C push on a merged branch blocks" exited 2 says "already merged"

# A failing check runs first, so the merged block must still show.
printf '{"scripts":{"build":"exit 1"}}\n' > "$MERGEDREPO/package.json"
gate_as "$MERGED" "git push origin feature/x"
check "a failing check does not hide the merged block" exited 2 says "build" says "already merged"

gate_as "OPEN https://github.com/o/r/pull/8" "git push origin feature/x"
check "a failing step names the step without a bypass hint" exited 2 says "[pre-push-gate] build" omits "SKIP_PUSH_GATE"

echo ""
echo "== package manager =="

# Only the tools the gate needs, plus stub managers that log their argv. A
# stub answers --version with STUB_VERSION and an audit with STUB_AUDIT_EXIT.
BIN="$TEST_ROOT/bin"
mkdir -p "$BIN"
for TOOL in bash cat dirname git grep head jq ls node python3 sed tail; do
  TOOL_PATH=$(command -v "$TOOL") || { echo "Missing required tool: $TOOL" >&2; exit 1; }
  ln -s "$TOOL_PATH" "$BIN/$TOOL"
done

make_stub() {
  stub "$BIN" "$1" <<'STUB'
#!/bin/bash
echo "${0##*/} $*" >> "$STUB_LOG"
case " $* " in
  *" --version "*) echo "${STUB_VERSION:-1.0.0}" ;;
  *" audit "*) exit "${STUB_AUDIT_EXIT:-0}" ;;
esac
exit 0
STUB
}
make_stub npm
make_stub pnpm

PM_MANIFEST='{"scripts":{"lint":"x","build":"x"}}'

# pm_project <name> [package.json]: a repo with node_modules. Prints its path.
pm_project() {
  local dir="$TEST_ROOT/pm-$1"
  mkdir -p "$dir/node_modules"
  git -C "$dir" init -q
  printf '%s\n' "${2:-$PM_MANIFEST}" > "$dir/package.json"
  echo "$dir"
}

# run_pm_gate <dir>: runs the gate under the stub PATH, and starts STUB_LOG empty.
run_pm_gate() {
  : > "$STUB_LOG"
  PATH="$BIN" STUB_LOG="$STUB_LOG" run_gate "$1"
}

logged() { grep -qxF -- "$1" "$STUB_LOG"; }
never_ran() { ! grep -q -- "^$1 " "$STUB_LOG"; }


REPO=$(pm_project pnpm-field '{"packageManager":"pnpm@10.4.1","scripts":{"lint":"x","build":"x"}}')
run_pm_gate "$REPO"
check "the packageManager field selects pnpm and passes" exited 0
check "scripts run through pnpm with --silent before run" logged "pnpm --silent run lint"
check "the audit uses the pnpm non-JSON form" logged "pnpm audit --audit-level critical"
check "npm never runs in a pnpm repo" never_ran npm

REPO=$(pm_project pnpm-lock)
: > "$REPO/pnpm-lock.yaml"
run_pm_gate "$REPO"
check "pnpm-lock.yaml selects pnpm" logged "pnpm --silent run build"

REPO=$(pm_project field-wins '{"packageManager":"pnpm@10.4.1","scripts":{}}')
: > "$REPO/package-lock.json"
run_pm_gate "$REPO"
check "the packageManager field beats a stray package-lock.json" \
  logged "pnpm audit --audit-level critical"

REPO=$(pm_project workspace)
: > "$REPO/pnpm-lock.yaml"
mkdir -p "$REPO/apps/web/node_modules"
echo '{"scripts":{"build":"x"}}' > "$REPO/apps/web/package.json"
run_pm_gate "$REPO/apps/web"
check "a push from a workspace package finds the root lockfile" logged "pnpm --silent run build"

REPO=$(pm_project pnpm-critical)
: > "$REPO/pnpm-lock.yaml"
STUB_AUDIT_EXIT=1 run_pm_gate "$REPO"
check "a failing pnpm audit blocks" exited 2
check "the block names the audit step" says "audit FAILED"

REPO=$(pm_project pnpm-fast '{"packageManager":"pnpm@10.4.1","scripts":{"verify:fast":"x"}}')
run_pm_gate "$REPO"
check "verify:fast runs through the repo's manager" logged "pnpm run verify:fast"

REPO=$(pm_project npm-lock)
: > "$REPO/package-lock.json"
run_pm_gate "$REPO"
check "package-lock.json passes" exited 0
check "scripts run through npm" logged "npm --silent run lint"
check "the audit uses npm" logged "npm audit --audit-level=critical"

REPO=$(pm_project no-lock)
run_pm_gate "$REPO"
check "no field and no lockfile falls back to npm" logged "npm audit --audit-level=critical"

rm "$BIN/pnpm"
REPO=$(pm_project pnpm-missing)
: > "$REPO/pnpm-lock.yaml"
run_pm_gate "$REPO"
check "a missing package manager blocks" exited 2
check "the block names the missing manager" says "uses pnpm, which is not on PATH"
make_stub pnpm

REPO=$(pm_project no-modules '{"scripts":{"lint":"x"},"devDependencies":{"x":"1.0.0"}}')
: > "$REPO/pnpm-lock.yaml"
rmdir "$REPO/node_modules"
run_pm_gate "$REPO"
check "a missing node_modules blocks when dependencies are declared" exited 2
check "the block names the pnpm install" says "[pre-push-gate]" says "run 'pnpm install' there first"

REPO=$(pm_project no-deps '{"scripts":{"lint":"x"},"peerDependencies":{"x":"*"}}')
rmdir "$REPO/node_modules"
run_pm_gate "$REPO"
check "a repo declaring no dependencies needs no node_modules" exited 0 logged "npm --silent run lint"

REPO=$(pm_project pnpm-husky)
: > "$REPO/pnpm-lock.yaml"
git -C "$REPO" config core.hooksPath .husky/_
run_pm_gate "$REPO"
check "a missing hooksPath directory names the pnpm install" says "Run 'pnpm install' in"

echo ""
echo "== audit only when the lockfile changed =="

# A repo pushed to a bare origin, so @{upstream} and origin/HEAD resolve.
REPO=$(pm_project lock-upstream)
echo '{}' > "$REPO/package-lock.json"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "chore: init"
git init -q --bare "$TEST_ROOT/lock-origin.git"
git -C "$REPO" remote add origin "$TEST_ROOT/lock-origin.git"
git -C "$REPO" push -q -u origin HEAD 2>/dev/null
git -C "$REPO" remote set-head origin -a >/dev/null 2>&1
git -C "$REPO" commit -q --allow-empty -m "fix: touch nothing"
run_pm_gate "$REPO"
check "an unchanged lockfile skips npm audit" exited 0 says "audit skipped" never_ran "npm audit"

echo '{"lockfileVersion":3}' > "$REPO/package-lock.json"
git -C "$REPO" commit -q -am "chore: bump lock"
run_pm_gate "$REPO"
check "a changed lockfile runs npm audit" logged "npm audit --audit-level=critical"

git -C "$REPO" branch -q --unset-upstream
run_pm_gate "$REPO"
check "without an upstream, origin/HEAD is the base" logged "npm audit --audit-level=critical"
git -C "$REPO" reset -q --hard HEAD~1
run_pm_gate "$REPO"
check "origin/HEAD with an unchanged lockfile skips the audit" says "audit skipped"

echo ""
echo "== main checkout and worktree =="

# verify:fast marks the directory it ran in. The main checkout's marker
# proves the gate ran the wrong checkout's checks.
MAIN="$TEST_ROOT/main-checkout"
mkdir -p "$MAIN"
printf '%s\n' '{"scripts":{"verify:fast":"touch ran-here"}}' > "$MAIN/package.json"
make_repo "$MAIN"
LANE="$MAIN/.claude/worktrees/lane"
git -C "$MAIN" worktree add -q -b feature/lane "$LANE"

# run_lane <cwd> <command>: the gate with CLAUDE_PROJECT_DIR on the main checkout.
run_lane() {
  rm -f "$MAIN/ran-here" "$LANE/ran-here"
  OUT=$(payload "$2" "$1" | (cd "$TEST_ROOT" && CLAUDE_PROJECT_DIR="$MAIN" SKIP_PUSH_GATE="" \
    bash "$PROJECT_DIR/hooks/pre-push-gate.sh" 2>&1))
  STATUS=$?
}
run_lane "$MAIN" "git -C \"$LANE\" push origin feature/lane"
check "a dependency-free worktree without node_modules passes" exited 0
check "a quoted git -C worktree push from the main checkout runs the worktree's checks" test -f "$LANE/ran-here"
check "the main checkout's checks do not run for a worktree push" not test -f "$MAIN/ran-here"
run_lane "$LANE" "git push origin feature/lane"
check "a push from the worktree cwd checks the worktree" test -f "$LANE/ran-here"
run_lane "$LANE" "cd \"$MAIN\" && git push origin main"
check "a cd to the main checkout beats the worktree cwd" test -f "$MAIN/ran-here"

make_stub yarn

REPO=$(pm_project yarn-classic)
: > "$REPO/yarn.lock"
STUB_VERSION=1.22.22 run_pm_gate "$REPO"
check "yarn.lock with Yarn Classic passes" exited 0
check "scripts run through yarn run" logged "yarn run lint"
check "Yarn Classic audits with yarn audit" logged "yarn audit --level critical"

STUB_VERSION=1.22.22 STUB_AUDIT_EXIT=12 run_pm_gate "$REPO"
check "Yarn Classic high and moderate findings (mask 12) pass" exited 0

STUB_VERSION=1.22.22 STUB_AUDIT_EXIT=17 run_pm_gate "$REPO"
check "Yarn Classic critical findings (mask 17) block" exited 2

REPO=$(pm_project yarn-berry '{"packageManager":"yarn@4.5.0","scripts":{"build":"x"}}')
STUB_VERSION=4.5.0 run_pm_gate "$REPO"
check "the packageManager field selects Yarn Berry and passes" exited 0
check "Yarn Berry audits every workspace and transitive dep" \
  logged "yarn npm audit --all --recursive --severity critical"

STUB_VERSION=4.5.0 STUB_AUDIT_EXIT=1 run_pm_gate "$REPO"
check "a failing Yarn Berry audit blocks" exited 2

finish
