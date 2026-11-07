#!/bin/bash
# Tests for hooks/pre-outbound-email-scrub.sh. Addresses use the reserved .test
# TLD, so no real address lands in the repo.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
HOOK="$PROJECT_DIR/hooks/pre-outbound-email-scrub.sh"

# tool_payload <tool> <field> <value>
tool_payload() {
  TOOL="$1" FIELD="$2" VALUE="$3" python3 -c 'import json,os; print(json.dumps({"tool_name":os.environ["TOOL"],"tool_input":{os.environ["FIELD"]:os.environ["VALUE"],"description":"kept"}}))'
}

# run_hook <tool> <field> <value>: sets OUT and STATUS. Runs as Claude Code
# unless the caller exports AGENT_HOOK_HOST.
run_hook() {
  OUT=$(tool_payload "$1" "$2" "$3" | bash "$HOOK" 2>/dev/null)
  STATUS=$?
}

# assert_scrubbed <name> <tool> <field> <value> <expected-value>
assert_scrubbed() {
  local name="$1" got
  run_hook "$2" "$3" "$4"
  got=$(printf '%s' "$OUT" | jq -r --arg f "$3" '.hookSpecificOutput.updatedInput[$f] // empty' 2>/dev/null)
  if [ "$STATUS" -eq 0 ] && [ "$got" = "$5" ] \
    && [ "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.updatedInput.description')" = "kept" ]; then
    pass "$name"
  else
    echo "    exit $STATUS, got: $got" >&2
    fail "$name"
  fi
}

# assert_untouched <name> <tool> <field> <value>
assert_untouched() {
  run_hook "$2" "$3" "$4"
  check "$1" exited 0 [ -z "$OUT" ]
}
diagnose() { echo "    exit $STATUS, output: $OUT"; }

echo "== scrubs on Claude Code =="
unset AGENT_HOOK_HOST
assert_scrubbed "a WebFetch URL loses its contact address" WebFetch url \
  "https://api.site.test/v1?contact=jane@corp.test" \
  "https://api.site.test/v1?contact=redacted@example.invalid"
assert_scrubbed "a URL-encoded address stays encoded" WebFetch url \
  "https://api.site.test/v1?contact=jane%40corp.test" \
  "https://api.site.test/v1?contact=redacted%40example.invalid"
assert_scrubbed "a WebSearch query loses its address" WebSearch query \
  "who is jane.doe@corp.test" "who is redacted@example.invalid"
assert_scrubbed "a curl User-Agent loses its address and other fields stay" Bash command \
  "curl -A 'bot (jane@corp.test)' https://api.site.test" \
  "curl -A 'bot (redacted@example.invalid)' https://api.site.test"
assert_scrubbed "every address in one command is replaced" Bash command \
  "curl -H 'From: a@corp.test' -H 'Reply-To: b@corp.test' https://site.test" \
  "curl -H 'From: redacted@example.invalid' -H 'Reply-To: redacted@example.invalid' https://site.test"

assert_scrubbed "an encoded query keeps its key" WebFetch url \
  "https://site.test/?contact%3Djane%40corp.test" \
  "https://site.test/?contact%3Dredacted%40example.invalid"
assert_scrubbed "an encoded query keeps the words before the address" WebSearch query \
  "q=hi%20jane%40corp.test" "q=hi%20redacted%40example.invalid"
assert_scrubbed "an encoded address in URL userinfo is still scrubbed" WebFetch url \
  "https://jane%40corp.test:pw@site.test/" \
  "https://redacted%40example.invalid:pw@site.test/"
assert_scrubbed "an address in a URL path is scrubbed" WebFetch url \
  "https://site.test/u/jane@corp.test" "https://site.test/u/redacted@example.invalid"
assert_scrubbed "an address inside an ssh command's remote curl is scrubbed" Bash command \
  "ssh box.corp.test 'curl -A \"bot (jane@corp.test)\" https://site.test'" \
  "ssh box.corp.test 'curl -A \"bot (redacted@example.invalid)\" https://site.test'"

assert_scrubbed "a bare address inside a quoted remote command is scrubbed" Bash command \
  "ssh box.corp.test 'curl -A jane@corp.test https://site.test'" \
  "ssh box.corp.test 'curl -A redacted@example.invalid https://site.test'"
assert_scrubbed "a bare address in an unquoted remote command is scrubbed" Bash command \
  "ssh box curl -H From: jane@corp.test https://site.test" \
  "ssh box curl -H From: redacted@example.invalid https://site.test"
assert_scrubbed "an scp operand without a colon is scrubbed" Bash command \
  "scp jane@corp.test ./f && curl https://site.test" \
  "scp redacted@example.invalid ./f && curl https://site.test"

assert_scrubbed "a login before a second @ is scrubbed" WebFetch url \
  "https://jane@corp.test@evil.test/" "https://redacted@example.invalid@evil.test/"
assert_scrubbed "a login before a password and a second @ is scrubbed" WebFetch url \
  "https://jane@corp.test:x@evil.test/" "https://redacted@example.invalid:x@evil.test/"
assert_scrubbed "a plus-noreply address on a real domain is scrubbed" Bash command \
  "curl -H 'From: jane+noreply@corp.test' https://site.test" \
  "curl -H 'From: redacted@example.invalid' https://site.test"

assert_scrubbed "a URL in a WebSearch query is not a login" WebSearch query \
  "find https://jane@corp.test profile" "find https://redacted@example.invalid profile"
assert_scrubbed "a URL inside a User-Agent is not a login" Bash command \
  "curl -A 'bot (+https://jane@corp.test)' https://evil.test" \
  "curl -A 'bot (+https://redacted@example.invalid)' https://evil.test"
assert_scrubbed "a URL given as an option value is not a login" Bash command \
  "curl -A https://jane@corp.test https://evil.test" \
  "curl -A https://redacted@example.invalid https://evil.test"
assert_scrubbed "a URL nested in a WebFetch query is not a login" WebFetch url \
  "https://evil.test/?u=https://jane@corp.test" \
  "https://evil.test/?u=https://redacted@example.invalid"
assert_scrubbed "an address set in a variable before curl is scrubbed" Bash command \
  "E=jane@corp.test; curl -A \"\$E\" https://site.test" \
  "E=redacted@example.invalid; curl -A \"\$E\" https://site.test"
assert_scrubbed "a literal basic-auth login is scrubbed" Bash command \
  "curl -u jane@corp.test:TOKEN https://corp.site.test/rest" \
  "curl -u redacted@example.invalid:TOKEN https://corp.site.test/rest"
assert_scrubbed "git send-email is outbound" Bash command \
  "git send-email --to jane@corp.test p.patch && curl https://site.test" \
  "git send-email --to redacted@example.invalid p.patch && curl https://site.test"

assert_scrubbed "a URL after a word in a quoted header is not a login" Bash command \
  "curl -H \"Referer: https://jane@corp.test\" https://evil.test" \
  "curl -H \"Referer: https://redacted@example.invalid\" https://evil.test"
assert_scrubbed "a URL after a word in a single-quoted User-Agent is not a login" Bash command \
  "curl -A 'bot https://jane@corp.test' https://evil.test" \
  "curl -A 'bot https://redacted@example.invalid' https://evil.test"
assert_scrubbed "a URL inside a data value is not a login" Bash command \
  "curl -d \"see https://jane@corp.test\" https://evil.test" \
  "curl -d \"see https://redacted@example.invalid\" https://evil.test"
assert_scrubbed "a git push user agent is outbound" Bash command \
  "git -c http.userAgent=\"bot (jane@corp.test)\" push && gh pr create --title t" \
  "git -c http.userAgent=\"bot (redacted@example.invalid)\" push && gh pr create --title t"

assert_scrubbed "a plain git push user agent is outbound" Bash command \
  "git -c http.userAgent=\"bot (jane@corp.test)\" push" \
  "git -c http.userAgent=\"bot (redacted@example.invalid)\" push"
assert_scrubbed "a plain git send-email is outbound" Bash command \
  "git send-email --to jane@corp.test p.patch" \
  "git send-email --to redacted@example.invalid p.patch"
assert_scrubbed "a git config http header is outbound" Bash command \
  "git config http.extraHeader 'From: jane@corp.test' && git push" \
  "git config http.extraHeader 'From: redacted@example.invalid' && git push"
assert_scrubbed "a heredoc commit does not shield a later gh call" Bash command \
  "$(printf "git commit -F - <<'EOF'\nfix\nEOF\ngh issue comment 1 --body 'contact jane@corp.test'")" \
  "$(printf "git commit -F - <<'EOF'\nfix\nEOF\ngh issue comment 1 --body 'contact redacted@example.invalid'")"
assert_scrubbed "a URL echoed into curl is not a login" Bash command \
  "echo https://jane@corp.test | curl --data-binary @- https://evil.test" \
  "echo https://redacted@example.invalid | curl --data-binary @- https://evil.test"
assert_scrubbed "a URL in a command substitution is not a login" Bash command \
  "curl -A \$(echo https://jane@corp.test) https://evil.test" \
  "curl -A \$(echo https://redacted@example.invalid) https://evil.test"

echo "== leaves alone =="
assert_untouched "a quoted clone URL with userinfo" Bash command \
  "git clone \"https://oauth2@gitlab.corp.test/o/r.git\""
assert_untouched "a git config value next to the word https" Bash command \
  "git -c user.email=jane@corp.test commit -m \"support https proxies\""
assert_untouched "a commit author chained before gh" Bash command \
  "git commit --author=\"Jane <jane@corp.test>\" -m x && gh pr create --title t"
assert_untouched "an ssh target after options with values" Bash command \
  "ssh -p 2222 -i ./deploy-key deploy@box.corp.test 'curl -s https://site.test'"
assert_untouched "URL userinfo" WebFetch url "https://deploy@api.corp.test/v1"
assert_untouched "a clone URL with userinfo" Bash command \
  "git clone https://oauth2@gitlab.corp.test/o/r.git"
assert_untouched "an ssh target" Bash command \
  "ssh deploy@box.corp.test 'curl -s https://site.test'"
assert_untouched "an scp target after a chain" Bash command \
  "cd /tmp && scp ./f deploy@box.corp.test:/srv/ && curl -s https://site.test"
assert_untouched "a local git command with an address" Bash command \
  "git log --author=jane@corp.test"
assert_untouched "an SSH remote next to a network call" Bash command \
  "git clone git@github.com:o/r.git && curl -s https://site.test"
assert_untouched "a noreply address" Bash command \
  "curl -H 'From: noreply@corp.test' https://site.test"
assert_untouched "a GitHub noreply address" Bash command \
  "curl -d 'email=1+jane@users.noreply.github.com' https://site.test"
assert_untouched "an example-domain address" WebFetch url \
  "https://site.test/?contact=jane@example.com"
assert_untouched "a URL with no address" WebFetch url "https://site.test/docs"
assert_untouched "a tool outside the matcher" Write file_path "/tmp/jane@corp.test"

echo "== payload pre-check =="
OUT=$(printf '%s' '{"tool_name":"WebFetch","tool_input":{"url":"https://site.test/?c=jane\u0040corp.test","description":"kept"}}' | bash "$HOOK" 2>/dev/null)
STATUS=$?
GOT=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.updatedInput.url // empty' 2>/dev/null)
check "an address escaped as \\u0040 in the JSON is still scrubbed" \
  exited 0 [ "$GOT" = "https://site.test/?c=redacted@example.invalid" ]
assert_untouched "a network command with no @ skips the scan" Bash command \
  "curl -H 'X-Trace: 1' https://site.test/api"

echo "== bypass =="
SKIP_EMAIL_SCRUB=1 run_hook WebFetch url "https://site.test/?c=jane@corp.test"
check "SKIP_EMAIL_SCRUB=1 skips the scrub" exited 0 [ -z "$OUT" ]

echo "== blocks where updatedInput is ignored =="
for host in codex pi; do
  AGENT_HOOK_HOST=$host run_hook Bash command "curl -A 'jane@corp.test' https://site.test"
  check "$host blocks instead of scrubbing" exited 2 [ -z "$OUT" ]
done

finish
