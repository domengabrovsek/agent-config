#!/bin/bash
# Tests for the action-ref check in hooks/post-edit-lint.sh: own actions stay
# at @main, and every third-party action is pinned to a SHA. Own is the owner
# of the repo's origin remote, plus any owners in OWN_ACTION_OWNERS.

set -u
# A value from the caller's shell would change which owners count as own.
unset OWN_ACTION_OWNERS

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$PROJECT_DIR/hooks/post-edit-lint.sh"
SHA=11bd71901bbe5b1630ceea73d27597364c9af683
PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); echo "ok - $1"; }
fail() { FAILED=$((FAILED + 1)); echo "not ok - $1" >&2; }

REPO=$(mktemp -d "${TMPDIR:-/tmp}/action-pins.XXXXXX")
trap 'rm -rf "$REPO"' EXIT
git -C "$REPO" init -q
mkdir -p "$REPO/.github/workflows" "$REPO/.github/actions/setup" "$REPO/config"

set_origin() {
  git -C "$REPO" remote remove origin 2>/dev/null
  [ -n "$1" ] && git -C "$REPO" remote add origin "$1"
}

# assert_file <name> <path relative to the repo> <content> <expected-exit> [env...]
# The file stays untracked, so the hook reads every line as newly added.
assert_file() {
  local name="$1" path="$REPO/$2" content="$3" want="$4" got
  shift 4
  printf '%s\n' "$content" > "$path"
  printf '{"tool_input":{"file_path":"%s"}}' "$path" | env "$@" bash "$HOOK" >/dev/null 2>&1
  got=$?
  rm -f "$path"
  if [ "$got" -eq "$want" ]; then pass "$name"; else
    echo "    want exit $want, got $got" >&2
    fail "$name"
  fi
}

WF=.github/workflows/ci.yml

echo "== own actions stay at @main =="
set_origin git@github.com:domengabrovsek/sample.git
assert_file "an own action at @main passes" "$WF" \
  "      - uses: domengabrovsek/github-actions/.github/actions/checkout@main" 0
assert_file "an own reusable workflow at @main passes" "$WF" \
  "    uses: domengabrovsek/github-actions/.github/workflows/notify.yml@main" 0
assert_file "an own action pinned to a SHA blocks" "$WF" \
  "      - uses: domengabrovsek/github-actions/.github/actions/checkout@$SHA # main" 2
assert_file "the owner match ignores case" "$WF" \
  "      - uses: DomenGabrovsek/github-actions/.github/actions/checkout@$SHA" 2
assert_file "another owner's action at @main is third-party" "$WF" \
  "      - uses: acme/tools@main" 2
assert_file "OWN_ACTION_OWNERS adds owners to the origin's" "$WF" \
  "      - uses: acme/tools@main" 0 OWN_ACTION_OWNERS=acme,other

echo
echo "== the owner comes from the origin remote =="
set_origin https://github.com/acme/app.git
assert_file "an https origin makes its owner own" "$WF" \
  "      - uses: acme/shared/.github/actions/build@main" 0
assert_file "under another owner, domengabrovsek actions are third-party" "$WF" \
  "      - uses: domengabrovsek/github-actions/.github/actions/checkout@main" 2
set_origin ssh://git@github.com/acme/app.git
assert_file "an ssh:// origin makes its owner own" "$WF" \
  "      - uses: acme/shared@main" 0
set_origin git@github-work:acme/app.git
assert_file "an ssh host alias origin makes its owner own" "$WF" \
  "      - uses: acme/shared@main" 0
set_origin ""
assert_file "with no origin, every action needs a SHA" "$WF" \
  "      - uses: acme/shared@main" 2
assert_file "with no origin, OWN_ACTION_OWNERS still applies" "$WF" \
  "      - uses: acme/shared@main" 0 OWN_ACTION_OWNERS=acme
set_origin git@github.com:domengabrovsek/sample.git

echo
echo "== third-party actions are pinned to a SHA =="
assert_file "a SHA pin with a version comment passes" "$WF" \
  "      - uses: actions/checkout@$SHA # v4.2.2" 0
assert_file "a version tag blocks" "$WF" \
  "      - uses: actions/checkout@v4" 2
assert_file "a quoted version tag blocks" "$WF" \
  "      - uses: \"actions/checkout@v4\"" 2
assert_file "a branch ref blocks" "$WF" \
  "        uses: dorny/paths-filter@main" 2
assert_file "a short SHA blocks" "$WF" \
  "      - uses: actions/checkout@11bd719" 2
assert_file "a composite action.yml is checked too" .github/actions/setup/action.yml \
  "    - uses: actions/setup-node@v4" 2

echo
echo "== refs the rule does not cover =="
assert_file "a local action passes" "$WF" \
  "      - uses: ./.github/actions/setup" 0
assert_file "a docker image passes" "$WF" \
  "      - uses: docker://alpine:3.20" 0
assert_file "a uses: line outside workflows is ignored" config/tools.yml \
  "uses: actions/checkout@v4" 0
assert_file "SKIP_POST_EDIT_LINT=1 bypasses the check" "$WF" \
  "      - uses: actions/checkout@v4" 0 SKIP_POST_EDIT_LINT=1

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
