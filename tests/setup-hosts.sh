#!/bin/bash
# Integration tests for the multi-host bootstrap. Every scenario uses a
# disposable HOME and a fake source repo; the caller's home is never read.

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/harness.sh
. "$PROJECT_DIR/tests/lib/harness.sh"
SETUP="$PROJECT_DIR/scripts/setup-hosts.sh"
WRAPPER="$PROJECT_DIR/scripts/setup-symlinks.sh"
harness_init setup-hosts

# quiet <command...>: runs the command with its output kept for diagnose and
# for later greps of $CASE_DIR/output.
quiet() { "$@" > "$CASE_DIR/output" 2>&1; }

diagnose() { [ ! -f "${CASE_DIR:-}/output" ] || sed -n '1,200p' "$CASE_DIR/output"; }

new_case() {
  CASE_DIR="$TEST_ROOT/$1"
  TEST_HOME="$CASE_DIR/home"
  TEST_REPO="$CASE_DIR/repo"
  mkdir -p "$TEST_HOME" "$TEST_REPO/.github" "$TEST_REPO/scripts"
  TEST_REPO=$(cd "$TEST_REPO" && pwd)
  for PATH_NAME in agents hooks rules skills scripts docs references templates mods; do
    mkdir -p "$TEST_REPO/$PATH_NAME"
  done
  : > "$TEST_REPO/AGENTS.md"
  : > "$TEST_REPO/settings.json"
  : > "$TEST_REPO/scripts/statusline.sh"
  : > "$TEST_REPO/.github/pull_request_template.md"
  mkdir -p "$TEST_REPO/pi/extensions"
  : > "$TEST_REPO/pi/settings.json"
  : > "$TEST_REPO/pi/models.json"
  : > "$TEST_REPO/pi/mcp.json"
  : > "$TEST_REPO/pi/extensions/statusline.ts"
}

run_setup() {
  PI_CONFIG_DIRS="$TEST_HOME/.pi/agent $TEST_HOME/.pi-personal/agent" \
  PI_CODING_AGENT_DIR="" \
  CLAUDE_CONFIG_DIRS="$TEST_HOME/.claude $TEST_HOME/.claude-personal" \
  HOME="$TEST_HOME" \
  CODEX_HOME="$TEST_HOME/.codex" \
  CLAUDE_CONFIG_DIR="$TEST_HOME/.claude" \
  AGENT_CONFIG_REPO="$TEST_REPO" \
    bash "$SETUP" "$@"
}

run_setup_at() {
  HOME="$TEST_HOME" CODEX_HOME="$TEST_HOME/.codex" AGENT_CONFIG_REPO="$TEST_REPO" \
    bash "$@"
}

run_setup_with_pi_dir() {
  PI_CONFIG_DIRS="" \
  PI_CODING_AGENT_DIR="$1" \
  HOME="$TEST_HOME" \
  CODEX_HOME="$TEST_HOME/.codex" \
  CLAUDE_CONFIG_DIR="$TEST_HOME/.claude" \
  AGENT_CONFIG_REPO="" \
  CLAUDE_DOTFILES_REPO="$TEST_REPO" \
    bash "$SETUP" "${@:2}"
}

run_setup_bare() {
  HOME="$TEST_HOME" \
  AGENT_CONFIG_REPO="$TEST_REPO" \
    bash "$SETUP" "$@"
}

run_wrapper() {
  HOME="$TEST_HOME" \
  CODEX_HOME="$TEST_HOME/.codex" \
  CLAUDE_CONFIG_DIR="$TEST_HOME/.claude" \
  AGENT_CONFIG_REPO="" \
  CLAUDE_DOTFILES_REPO="$TEST_REPO" \
    bash "$WRAPPER" "$@"
}

assert_link() {
  [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]
}

backup_count() {
  BACKUP_BASE="$1"
  COUNT=0
  for FOUND in "$BACKUP_BASE".bak.*; do
    [ -e "$FOUND" ] || [ -L "$FOUND" ] || continue
    COUNT=$((COUNT + 1))
  done
  printf "%s\n" "$COUNT"
}

# Check is auditable and has no side effects on an unconfigured home.
new_case check_no_mutation
check "check reports drift" not quiet run_setup --check
check "check creates no host directories" test ! -e "$TEST_HOME/.claude"
check "check creates no Codex config" test ! -e "$TEST_HOME/.codex"
check "check creates no shared skills path" test ! -e "$TEST_HOME/.agents"

# A clean apply configures every selected host and Codex's narrow fallback.
new_case apply_all
check "apply configures all hosts" quiet run_setup --apply
while IFS='|' read -r NAME RELATIVE; do
  check "Claude manifest includes $NAME" assert_link "$TEST_HOME/.claude/$NAME" "$TEST_REPO/$RELATIVE"
done <<'EOF'
CLAUDE.md|AGENTS.md
settings.json|settings.json
agents|agents
hooks|hooks
rules|rules
skills|skills
scripts|scripts
docs|docs
references|references
templates|templates
mods|mods
statusline.sh|scripts/statusline.sh
pull_request_template.md|.github/pull_request_template.md
EOF
while IFS='|' read -r NAME RELATIVE; do
  check "Claude personal dir gets $NAME" assert_link "$TEST_HOME/.claude-personal/$NAME" "$TEST_REPO/$RELATIVE"
done <<'EOF'
CLAUDE.md|AGENTS.md
settings.json|settings.json
hooks|hooks
rules|rules
EOF
check "Codex AGENTS.md is shared" assert_link "$TEST_HOME/.codex/AGENTS.md" "$TEST_REPO/AGENTS.md"
check "Pi base dir receives instructions and resources" assert_link "$TEST_HOME/.pi/agent/AGENTS.md" "$TEST_REPO/AGENTS.md" && assert_link "$TEST_HOME/.pi/agent/extensions" "$TEST_REPO/pi/extensions" && assert_link "$TEST_HOME/.pi/agent/settings.json" "$TEST_REPO/pi/settings.json" && assert_link "$TEST_HOME/.pi/agent/models.json" "$TEST_REPO/pi/models.json" && assert_link "$TEST_HOME/.pi/agent/agents" "$TEST_REPO/agents"
check "Pi personal dir receives instructions and resources" assert_link "$TEST_HOME/.pi-personal/agent/AGENTS.md" "$TEST_REPO/AGENTS.md" && assert_link "$TEST_HOME/.pi-personal/agent/extensions" "$TEST_REPO/pi/extensions" && assert_link "$TEST_HOME/.pi-personal/agent/settings.json" "$TEST_REPO/pi/settings.json" && assert_link "$TEST_HOME/.pi-personal/agent/models.json" "$TEST_REPO/pi/models.json" && assert_link "$TEST_HOME/.pi-personal/agent/agents" "$TEST_REPO/agents"
while IFS='|' read -r NAME RELATIVE; do
  check "shared root exposes $NAME" assert_link "$TEST_HOME/.agents/$NAME" "$TEST_REPO/$RELATIVE"
done <<'EOF'
skills|skills
rules|rules
scripts|scripts
templates|templates
references|references
agents|agents
pull_request_template.md|.github/pull_request_template.md
EOF
check "Codex fallback is created" grep -Fq 'project_doc_fallback_filenames = ["CLAUDE.md"]' "$TEST_HOME/.codex/config.toml"
check "Codex status line is created" grep -Fq 'status_line = ["project-name", "git-branch", "model-with-reasoning", "context-used", "five-hour-limit", "weekly-limit", "thread-credits", "estimated-thread-cost"]' "$TEST_HOME/.codex/config.toml"
check "Codex long context is created" grep -Fq 'model_context_window = 1050000' "$TEST_HOME/.codex/config.toml"
check "Codex long-context compaction limit is created" grep -Fq 'model_auto_compact_token_limit = 950000' "$TEST_HOME/.codex/config.toml"
check "clean check exits zero" quiet run_setup --check

# A Pi-only selection includes every shared resource Pi needs.
new_case pi_only
check "Pi-only apply succeeds" quiet run_setup --apply --host pi
check "Pi-only apply links instructions" assert_link "$TEST_HOME/.pi/agent/AGENTS.md" "$TEST_REPO/AGENTS.md"
check "Pi-only apply links the personal dir too" assert_link "$TEST_HOME/.pi-personal/agent/AGENTS.md" "$TEST_REPO/AGENTS.md" && assert_link "$TEST_HOME/.pi-personal/agent/extensions" "$TEST_REPO/pi/extensions" && assert_link "$TEST_HOME/.pi-personal/agent/settings.json" "$TEST_REPO/pi/settings.json" && assert_link "$TEST_HOME/.pi-personal/agent/models.json" "$TEST_REPO/pi/models.json" && assert_link "$TEST_HOME/.pi-personal/agent/agents" "$TEST_REPO/agents"
check "Pi base directory receives MCP config" assert_link "$TEST_HOME/.pi/agent/mcp.json" "$TEST_REPO/pi/mcp.json"
check "Pi personal directory receives MCP config" assert_link "$TEST_HOME/.pi-personal/agent/mcp.json" "$TEST_REPO/pi/mcp.json"
check "Pi-only apply links shared skills" assert_link "$TEST_HOME/.agents/skills" "$TEST_REPO/skills"
check "Pi-only apply links shared scripts" assert_link "$TEST_HOME/.agents/scripts" "$TEST_REPO/scripts"
check "Pi-only apply links shared templates" assert_link "$TEST_HOME/.agents/templates" "$TEST_REPO/templates"
check "Pi-only apply skips Codex" test ! -e "$TEST_HOME/.codex"
check "Pi-only check exits zero" quiet run_setup --check --host pi
check "Pi-only re-apply is idempotent" quiet run_setup --apply --host pi
check "Pi-only re-apply creates no instruction backup" test "$(backup_count "$TEST_HOME/.pi/agent/AGENTS.md")" -eq 0
check "Pi-only re-apply preserves MCP link" assert_link "$TEST_HOME/.pi/agent/mcp.json" "$TEST_REPO/pi/mcp.json"
check "Pi-only re-apply creates no MCP backup" test "$(backup_count "$TEST_HOME/.pi/agent/mcp.json")" -eq 0
check "Pi-only re-apply creates no skill backup" test "$(backup_count "$TEST_HOME/.agents/skills")" -eq 0

# Pi follows its native config-directory override.
new_case pi_custom_dir
CUSTOM_PI_DIR="$CASE_DIR/custom-pi"
check "Pi custom directory apply succeeds" quiet run_setup_with_pi_dir "$CUSTOM_PI_DIR" --apply --host pi
check "Pi custom directory receives instructions" assert_link "$CUSTOM_PI_DIR/AGENTS.md" "$TEST_REPO/AGENTS.md"
check "Pi custom directory receives extension and settings links" assert_link "$CUSTOM_PI_DIR/extensions" "$TEST_REPO/pi/extensions" && assert_link "$CUSTOM_PI_DIR/settings.json" "$TEST_REPO/pi/settings.json" && assert_link "$CUSTOM_PI_DIR/models.json" "$TEST_REPO/pi/models.json"
check "Pi custom directory receives MCP config" assert_link "$CUSTOM_PI_DIR/mcp.json" "$TEST_REPO/pi/mcp.json"
check "Pi default directory stays absent" test ! -e "$TEST_HOME/.pi"
check "Pi custom directory still gets shared skills" assert_link "$TEST_HOME/.agents/skills" "$TEST_REPO/skills"
check "Pi custom directory check exits zero" quiet run_setup_with_pi_dir "$CUSTOM_PI_DIR" --check --host pi

# Pi-only adoption recovers both host and shared-resource conflicts across
# every configured agent dir.
new_case pi_only_adopt
mkdir -p "$TEST_HOME/.pi/agent" "$TEST_HOME/.pi-personal/agent" "$TEST_HOME/.agents/skills"
printf "local instructions\n" > "$TEST_HOME/.pi/agent/AGENTS.md"
printf "personal instructions\n" > "$TEST_HOME/.pi-personal/agent/AGENTS.md"
printf "local skill\n" > "$TEST_HOME/.agents/skills/local-skill"
check "Pi-only apply refuses conflicts" not quiet run_setup --apply --host pi
check "Pi-only adopt resolves conflicts" quiet run_setup --apply --adopt --host pi
check "Pi-only adopt links instructions" assert_link "$TEST_HOME/.pi/agent/AGENTS.md" "$TEST_REPO/AGENTS.md"
check "Pi-only adopt links personal instructions" assert_link "$TEST_HOME/.pi-personal/agent/AGENTS.md" "$TEST_REPO/AGENTS.md"
check "Pi-only adopt links shared skills" assert_link "$TEST_HOME/.agents/skills" "$TEST_REPO/skills"
check "Pi-only adopt backs up instructions" test "$(backup_count "$TEST_HOME/.pi/agent/AGENTS.md")" -eq 1
check "Pi-only adopt backs up personal instructions" test "$(backup_count "$TEST_HOME/.pi-personal/agent/AGENTS.md")" -eq 1
check "Pi-only adopt backs up shared skills" test "$(backup_count "$TEST_HOME/.agents/skills")" -eq 1

# A Codex-only selection includes the shared skills it discovers.
new_case codex_only
check "Codex-only apply succeeds" quiet run_setup --apply --host codex
check "Codex-only apply links instructions" assert_link "$TEST_HOME/.codex/AGENTS.md" "$TEST_REPO/AGENTS.md"
check "Codex-only apply links shared skills" assert_link "$TEST_HOME/.agents/skills" "$TEST_REPO/skills"
check "Codex-only apply skips Pi" test ! -e "$TEST_HOME/.pi"

# Re-applying makes no backups or content changes.
new_case idempotent
check "first idempotence apply succeeds" quiet run_setup --apply
FIRST_CONFIG=$(cksum "$TEST_HOME/.codex/config.toml")
check "second idempotence apply succeeds" quiet run_setup --apply
SECOND_CONFIG=$(cksum "$TEST_HOME/.codex/config.toml")
check "idempotent config is unchanged" test "$FIRST_CONFIG" = "$SECOND_CONFIG"
check "idempotent apply creates no config backup" test "$(backup_count "$TEST_HOME/.codex/config.toml")" -eq 0

# Normal apply repairs missing paths but refuses exact conflicts.
new_case conflict_refusal
mkdir -p "$TEST_HOME/.agents/skills"
: > "$TEST_HOME/.agents/skills/local-skill"
check "apply refuses a real conflict" not quiet run_setup --apply
check "refused conflict is preserved" test -f "$TEST_HOME/.agents/skills/local-skill"
check "refused conflict is not replaced" test ! -L "$TEST_HOME/.agents/skills"
check "safe missing links still apply" assert_link "$TEST_HOME/.codex/AGENTS.md" "$TEST_REPO/AGENTS.md"

# Adopt moves content to an adjacent backup and never deletes it.
new_case adopt_backup
mkdir -p "$TEST_HOME/.agents/skills"
printf "keep me\n" > "$TEST_HOME/.agents/skills/local-skill"
check "adopt backs up a real conflict" quiet run_setup --apply --adopt
check "adopt installs the shared link" assert_link "$TEST_HOME/.agents/skills" "$TEST_REPO/skills"
ADOPTED_BACKUP=""
for FOUND in "$TEST_HOME/.agents/skills".bak.*; do
  [ -d "$FOUND" ] || continue
  ADOPTED_BACKUP="$FOUND"
done
check "adopt backup retains content" grep -Fq "keep me" "$ADOPTED_BACKUP/local-skill"

# Wrong symlinks are conflicts too: refused normally, recoverably adopted.
new_case wrong_symlink
mkdir -p "$TEST_HOME/.codex" "$CASE_DIR/other"
ln -s "$CASE_DIR/other" "$TEST_HOME/.codex/AGENTS.md"
check "wrong symlink is refused without adopt" not quiet run_setup --apply --host codex
check "wrong symlink remains untouched" assert_link "$TEST_HOME/.codex/AGENTS.md" "$CASE_DIR/other"
check "wrong symlink can be adopted" quiet run_setup --apply --adopt --host codex
check "adopt replaces wrong symlink" assert_link "$TEST_HOME/.codex/AGENTS.md" "$TEST_REPO/AGENTS.md"
check "wrong symlink itself is backed up" test "$(backup_count "$TEST_HOME/.codex/AGENTS.md")" -eq 1

# Existing Codex config is backed up before the root key is prepended.
new_case codex_existing
mkdir -p "$TEST_HOME/.codex"
printf '[features]\nweb_search = true\n' > "$TEST_HOME/.codex/config.toml"
check "existing Codex config gets safe fallback" quiet run_setup --apply --host codex
check "existing Codex config has fallback at root" test "$(sed -n '1p' "$TEST_HOME/.codex/config.toml")" = 'project_doc_fallback_filenames = ["CLAUDE.md"]'
check "existing Codex settings are preserved" grep -Fq 'web_search = true' "$TEST_HOME/.codex/config.toml"
check "existing Codex config gets status line" grep -Fq 'status_line = ["project-name", "git-branch", "model-with-reasoning", "context-used", "five-hour-limit", "weekly-limit", "thread-credits", "estimated-thread-cost"]' "$TEST_HOME/.codex/config.toml"
check "existing Codex config has one backup" test "$(backup_count "$TEST_HOME/.codex/config.toml")" -eq 1

# An existing tui table receives the default without creating a second table.
new_case codex_existing_tui
mkdir -p "$TEST_HOME/.codex"
printf '[tui]\nnotifications = true\n' > "$TEST_HOME/.codex/config.toml"
check "existing tui table gets status line" quiet run_setup --apply --host codex
check "existing tui setting is preserved" grep -Fq 'notifications = true' "$TEST_HOME/.codex/config.toml"
check "existing tui table is not duplicated" test "$(grep -c '^\[tui\]$' "$TEST_HOME/.codex/config.toml")" -eq 1
check "status line is inside existing tui table" test "$(sed -n '/^\[tui\]$/,/^\[/p' "$TEST_HOME/.codex/config.toml" | grep -c '^status_line = ')" -eq 1

# A custom status line is preserved while an independent fallback is added.
new_case codex_custom_status
mkdir -p "$TEST_HOME/.codex"
printf '[tui]\nstatus_line = ["thread-id"]\n' > "$TEST_HOME/.codex/config.toml"
check "custom Codex status line is preserved" quiet run_setup --apply --host codex
check "custom status line remains unchanged" grep -Fq 'status_line = ["thread-id"]' "$TEST_HOME/.codex/config.toml"
check "custom status config gets fallback" test "$(sed -n '1p' "$TEST_HOME/.codex/config.toml")" = 'project_doc_fallback_filenames = ["CLAUDE.md"]'
check "custom status migration has one backup" test "$(backup_count "$TEST_HOME/.codex/config.toml")" -eq 1

# A compatible fallback and custom status line are a complete no-op.
new_case codex_compatible
mkdir -p "$TEST_HOME/.codex"
printf 'project_doc_fallback_filenames = ["AGENT.md", "CLAUDE.md"]\nmodel_context_window = 1050000\nmodel_auto_compact_token_limit = 950000\n\n[tui]\nstatus_line = ["git-branch"]\n\n[features]\nhooks = true # shared hooks\n' > "$TEST_HOME/.codex/config.toml"
check "compatible Codex fallback is unchanged" quiet run_setup --apply --host codex
check "compatible custom status is unchanged" grep -Fq 'status_line = ["git-branch"]' "$TEST_HOME/.codex/config.toml"
check "compatible Codex config has no backup" test "$(backup_count "$TEST_HOME/.codex/config.toml")" -eq 0

new_case codex_incompatible
mkdir -p "$TEST_HOME/.codex"
printf 'project_doc_fallback_filenames = ["OTHER.md"]\n' > "$TEST_HOME/.codex/config.toml"
BEFORE=$(cksum "$TEST_HOME/.codex/config.toml")
check "different Codex fallback is refused" not quiet run_setup --apply --host codex
check "different Codex fallback is untouched" test "$BEFORE" = "$(cksum "$TEST_HOME/.codex/config.toml")"
check "different fallback creates no backup" test "$(backup_count "$TEST_HOME/.codex/config.toml")" -eq 0

new_case codex_check_no_mutation
mkdir -p "$TEST_HOME/.codex"
printf '[features]\nweb_search = true\n' > "$TEST_HOME/.codex/config.toml"
BEFORE=$(cksum "$TEST_HOME/.codex/config.toml")
check "Codex check reports missing fallback" not quiet run_setup --check --host codex
check "Codex check preserves existing config" test "$BEFORE" = "$(cksum "$TEST_HOME/.codex/config.toml")"
check "Codex check creates no backup" test "$(backup_count "$TEST_HOME/.codex/config.toml")" -eq 0

new_case codex_multiline
mkdir -p "$TEST_HOME/.codex"
printf 'project_doc_fallback_filenames = [\n  "CLAUDE.md",\n]\n' > "$TEST_HOME/.codex/config.toml"
check "multiline Codex fallback is refused" not quiet run_setup --apply --host codex

# Ambiguous tui layouts and duplicate status lines require a manual edit.
new_case codex_nested_tui
mkdir -p "$TEST_HOME/.codex"
printf 'project_doc_fallback_filenames = ["CLAUDE.md"]\n\n[tui.keymap]\nexample = "ctrl-e"\n' > "$TEST_HOME/.codex/config.toml"
BEFORE=$(cksum "$TEST_HOME/.codex/config.toml")
check "nested tui without parent is refused" not quiet run_setup --apply --host codex
check "nested tui config is untouched" test "$BEFORE" = "$(cksum "$TEST_HOME/.codex/config.toml")"

new_case codex_duplicate_status
mkdir -p "$TEST_HOME/.codex"
printf 'project_doc_fallback_filenames = ["CLAUDE.md"]\n\n[tui]\nstatus_line = ["git-branch"]\nstatus_line = ["thread-id"]\n' > "$TEST_HOME/.codex/config.toml"
BEFORE=$(cksum "$TEST_HOME/.codex/config.toml")
check "duplicate Codex status lines are refused" not quiet run_setup --apply --host codex
check "duplicate status config is untouched" test "$BEFORE" = "$(cksum "$TEST_HOME/.codex/config.toml")"

# Codex enables hooks inside an existing [features] table, not a second one.
new_case codex_existing_features
mkdir -p "$TEST_HOME/.codex"
printf '[features]\nweb_search = true\n' > "$TEST_HOME/.codex/config.toml"
check "existing features table gets hooks" quiet run_setup --apply --host codex
check "existing features table is not duplicated" test "$(grep -c '^\[features\]$' "$TEST_HOME/.codex/config.toml")" -eq 1
check "hooks flag is inside the features table" test "$(sed -n '/^\[features\]$/,/^\[/p' "$TEST_HOME/.codex/config.toml" | grep -c '^hooks = true$')" -eq 1
check "existing feature is preserved" grep -Fq 'web_search = true' "$TEST_HOME/.codex/config.toml"

new_case codex_hooks_disabled
mkdir -p "$TEST_HOME/.codex"
printf '[features]\nhooks = false\n' > "$TEST_HOME/.codex/config.toml"
BEFORE=$(cksum "$TEST_HOME/.codex/config.toml")
check "a disabled hooks feature is refused" not quiet run_setup --apply --host codex
check "disabled hooks config is untouched" test "$BEFORE" = "$(cksum "$TEST_HOME/.codex/config.toml")"

# Codex hooks.json registers the dispatcher once per registry event.
write_registry() {
  cat > "$TEST_REPO/settings.json" <<JSON
{"hooks": {
  "PreToolUse": [
    {"matcher": "Bash", "hooks": [{"type": "command", "command": "a", "timeout": 15}, {"type": "command", "command": "b"}]},
    {"matcher": "Write|Edit", "hooks": [{"type": "command", "command": "c", "timeout": 10}]}
  ],
  $1
  "Notification": [{"hooks": [{"type": "command", "command": "d"}]}]
}}
JSON
}
new_case codex_hooks
mkdir -p "$TEST_REPO/hooks/lib"
printf '#!/bin/bash\n' > "$TEST_REPO/hooks/lib/dispatch.sh"
chmod +x "$TEST_REPO/hooks/lib/dispatch.sh"
write_registry ""
HOOKS_JSON="$TEST_HOME/.codex/hooks.json"
check "check reports a missing Codex hooks file" not quiet run_setup --check --host codex
check "check creates no Codex hooks file" test ! -e "$HOOKS_JSON"
check "apply registers the dispatcher" quiet run_setup --apply --host codex
check "hooks file covers exactly the registry's Codex events" test "$(jq -c '.hooks | keys' "$HOOKS_JSON")" = '["PreToolUse"]'
check "the entry calls the dispatcher for its event" test "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$HOOKS_JSON")" = "'$TEST_REPO/hooks/lib/dispatch.sh' PreToolUse"
check "the entry budget sums the event's timeouts" test "$(jq '.hooks.PreToolUse[0].hooks[0].timeout' "$HOOKS_JSON")" -eq 85
check "the hooks feature is enabled" grep -Fxq 'hooks = true' "$TEST_HOME/.codex/config.toml"
check "check is clean after registering" quiet run_setup --check --host codex
FIRST_HOOKS=$(cksum "$HOOKS_JSON")
check "re-apply is idempotent" quiet run_setup --apply --host codex
check "re-apply leaves the hooks file unchanged" test "$FIRST_HOOKS" = "$(cksum "$HOOKS_JSON")"
check "re-apply creates no hooks backup" test "$(backup_count "$HOOKS_JSON")" -eq 0

write_registry '"SessionEnd": [{"hooks": [{"type": "command", "command": "e", "timeout": 30}]}],'
check "check reports a stale hooks file after a registry change" not quiet run_setup --check --host codex
check "apply regenerates a stale hooks file" quiet run_setup --apply --host codex
check "regenerated file gains the new event" test "$(jq -c '.hooks | keys' "$HOOKS_JSON")" = '["PreToolUse","SessionEnd"]'
check "regeneration keeps one backup" test "$(backup_count "$HOOKS_JSON")" -eq 1

new_case codex_hooks_foreign
mkdir -p "$TEST_REPO/hooks/lib" "$TEST_HOME/.codex"
printf '#!/bin/bash\n' > "$TEST_REPO/hooks/lib/dispatch.sh"
chmod +x "$TEST_REPO/hooks/lib/dispatch.sh"
write_registry ""
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"mine"}]}]}}\n' > "$TEST_HOME/.codex/hooks.json"
BEFORE=$(cksum "$TEST_HOME/.codex/hooks.json")
check "a user hooks file is refused" not quiet run_setup --apply --host codex
check "a refused user hooks file is untouched" test "$BEFORE" = "$(cksum "$TEST_HOME/.codex/hooks.json")"
check "a user hooks file can be adopted" quiet run_setup --apply --adopt --host codex
check "adopt installs the dispatcher" test "$(jq -c '.hooks | keys' "$TEST_HOME/.codex/hooks.json")" = '["PreToolUse"]'
check "adopt backs up the user hooks file" test "$(backup_count "$TEST_HOME/.codex/hooks.json")" -eq 1

# The legacy command selects only Claude and retains automatic safe adoption.
new_case legacy_wrapper
mkdir -p "$TEST_HOME/.claude"
printf 'local\n' > "$TEST_HOME/.claude/CLAUDE.md"
check "legacy wrapper applies and adopts Claude" quiet run_wrapper
check "legacy wrapper links Claude config" assert_link "$TEST_HOME/.claude/CLAUDE.md" "$TEST_REPO/AGENTS.md"
check "legacy wrapper backs up Claude conflict" test "$(backup_count "$TEST_HOME/.claude/CLAUDE.md")" -eq 1
check "legacy wrapper does not configure Codex" test ! -e "$TEST_HOME/.codex"
check "legacy wrapper does not configure Pi" test ! -e "$TEST_HOME/.pi"
# The shared root is host-neutral, so a Claude-only run creates it too:
# shared skills name ~/.agents paths and would break without it.
check "legacy wrapper links the shared root" assert_link "$TEST_HOME/.agents/skills" "$TEST_REPO/skills"
check "legacy --check remains report-only" quiet run_wrapper --check
check "legacy -n remains report-only" quiet run_wrapper -n
check "legacy --dry-run remains report-only" quiet run_wrapper --dry-run

# A machine records its scope once so an argument-free run stays correct. This
# is the drift-check extension's exact call shape: no flags, no environment.
new_case scope_file_narrows_hosts
mkdir -p "$TEST_HOME/.agents"
cat > "$TEST_HOME/.agents/hosts.env" <<'SCOPE'
: "${CLAUDE_CONFIG_DIRS:=$HOME/.claude}"
: "${PI_CONFIG_DIRS:=$HOME/.pi/agent}"
: "${HARNESS_SKIP_HOSTS:=codex}"
SCOPE
check "scope file applies with no arguments" quiet run_setup_bare --apply
check "scope file links the base claude dir" assert_link "$TEST_HOME/.claude/CLAUDE.md" "$TEST_REPO/AGENTS.md"
check "scope file links the base pi dir" assert_link "$TEST_HOME/.pi/agent/settings.json" "$TEST_REPO/pi/settings.json"
check "scope file skips the personal claude dir" test ! -e "$TEST_HOME/.claude-personal"
check "scope file skips the personal pi dir" test ! -e "$TEST_HOME/.pi-personal"
check "scope file skips codex" test ! -e "$TEST_HOME/.codex"
check "scope file still links shared skills" assert_link "$TEST_HOME/.agents/skills" "$TEST_REPO/skills"
check "argument-free check is clean after apply" quiet run_setup_bare --check

# Without a scope file the two-dir defaults stand, so existing machines are
# unaffected by the new lookup.
new_case scope_file_absent_keeps_defaults
check "no scope file still applies" quiet run_setup_bare --apply
check "no scope file links the personal claude dir" assert_link "$TEST_HOME/.claude-personal/CLAUDE.md" "$TEST_REPO/AGENTS.md"
check "no scope file links the personal pi dir" assert_link "$TEST_HOME/.pi-personal/agent/settings.json" "$TEST_REPO/pi/settings.json"
check "no scope file configures codex" test -e "$TEST_HOME/.codex/AGENTS.md"

# The := form means a real environment variable is never clobbered.
new_case scope_file_yields_to_environment
mkdir -p "$TEST_HOME/.agents"
cat > "$TEST_HOME/.agents/hosts.env" <<'SCOPE'
: "${PI_CONFIG_DIRS:=$HOME/.pi/agent}"
: "${HARNESS_SKIP_HOSTS:=codex pi}"
SCOPE
check "environment overrides the scope file" quiet env HOME="$TEST_HOME" AGENT_CONFIG_REPO="$TEST_REPO" PI_CONFIG_DIRS="$TEST_HOME/.pi-elsewhere/agent" HARNESS_SKIP_HOSTS="codex" bash "$SETUP" --apply
check "environment pi dir wins" assert_link "$TEST_HOME/.pi-elsewhere/agent/settings.json" "$TEST_REPO/pi/settings.json"
check "environment skip list wins" test ! -e "$TEST_HOME/.codex"
check "scope file pi dir is unused" test ! -e "$TEST_HOME/.pi/agent"

# An explicit --host is a direct instruction and outranks the skip list.
new_case explicit_host_beats_skip_list
mkdir -p "$TEST_HOME/.agents"
cat > "$TEST_HOME/.agents/hosts.env" <<'SCOPE'
: "${HARNESS_SKIP_HOSTS:=codex}"
SCOPE
check "explicit codex host runs despite the skip list" quiet run_setup_bare --apply --host codex
check "explicit codex host is configured" test -e "$TEST_HOME/.codex/AGENTS.md"

# AGENT_HOSTS_ENV relocates the file for machines that keep it elsewhere.
new_case scope_file_relocated
mkdir -p "$TEST_HOME/elsewhere"
cat > "$TEST_HOME/elsewhere/scope.env" <<'SCOPE'
: "${HARNESS_SKIP_HOSTS:=codex pi}"
SCOPE
check "relocated scope file applies" quiet env HOME="$TEST_HOME" AGENT_CONFIG_REPO="$TEST_REPO" AGENT_HOSTS_ENV="$TEST_HOME/elsewhere/scope.env" bash "$SETUP" --apply
check "relocated scope file skips codex" test ! -e "$TEST_HOME/.codex"
check "relocated scope file skips pi" test ! -e "$TEST_HOME/.pi"
check "relocated scope file still links claude" assert_link "$TEST_HOME/.claude/CLAUDE.md" "$TEST_REPO/AGENTS.md"

# Worktree cleanup deletes worktrees, so hosts must link the main checkout.
new_case run_from_worktree
cp "$SETUP" "$TEST_REPO/scripts/setup-hosts.sh"
GIT_CONFIG_GLOBAL=/dev/null make_repo "$TEST_REPO"
GIT_CONFIG_GLOBAL=/dev/null git -C "$TEST_REPO" worktree add -q -b side "$CASE_DIR/wt" main
MAIN_REAL=$(cd "$TEST_REPO" && pwd -P)
check "setup run from a worktree succeeds" quiet env HOME="$TEST_HOME" AGENT_CONFIG_REPO="" CLAUDE_DOTFILES_REPO="" \
  CLAUDE_CONFIG_DIRS="$TEST_HOME/.claude" HARNESS_SKIP_HOSTS="codex pi" \
  bash "$CASE_DIR/wt/scripts/setup-hosts.sh" --apply
check "setup run from a worktree links the main checkout" assert_link "$TEST_HOME/.claude/CLAUDE.md" "$MAIN_REAL/AGENTS.md"
check "setup run from a worktree says it links the main checkout" \
  grep -q "Linking hosts to the main checkout $MAIN_REAL" "$CASE_DIR/output"
check "an override naming a worktree is refused" not quiet env HOME="$TEST_HOME" AGENT_CONFIG_REPO="$CASE_DIR/wt" \
  CLAUDE_CONFIG_DIRS="$TEST_HOME/.claude" bash "$SETUP" --check --host claude
check "the refusal names the main checkout" grep -q "main checkout: $MAIN_REAL" "$CASE_DIR/output"

# The Codex editing lives in scripts/lib, found beside the script's real path.
new_case codex_lib_via_link
mkdir -p "$CASE_DIR/bin"
ln -s "$SETUP" "$CASE_DIR/bin/setup"
check "a linked script finds its Codex library" quiet run_setup_at "$CASE_DIR/bin/setup" --apply --host codex
check "the linked run writes the Codex config" test -f "$TEST_HOME/.codex/config.toml"

new_case codex_lib_missing
cp "$SETUP" "$CASE_DIR/setup-hosts.sh"
check "a missing Codex library is an issue" not quiet run_setup_at "$CASE_DIR/setup-hosts.sh" --check --host codex
check "the missing library is reported" grep -q "codex/config.toml *MISSING-SRC" "$CASE_DIR/output"

finish
