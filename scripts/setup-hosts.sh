#!/bin/bash
# Non-destructive bootstrap for shared Claude Code, Codex, and Pi config.
# Bash 3.2 compatible; replacements are always recoverable adjacent backups.

set -u

MODE=""
ADOPT=0
HOST="all"

usage() {
  cat <<'EOF'
Usage: scripts/setup-hosts.sh (--check|--apply) [--adopt] [--host HOST]

Modes:
  --check          Report drift without changing the filesystem.
  --apply          Create missing links and add safe Codex fallback config.
  --apply --adopt  Also move exact conflicts to timestamped backups, then link.

Hosts: all (default), claude, codex, pi, shared

Environment:
  AGENT_CONFIG_REPO     Repo to link (preferred generic override).
  CLAUDE_DOTFILES_REPO Backward-compatible repo override.
  CLAUDE_CONFIG_DIR    Claude config directory (default: ~/.claude).
  CLAUDE_CONFIG_DIRS   Space-separated claude dir list; overrides CLAUDE_CONFIG_DIR.
  CODEX_HOME           Codex config directory (default: ~/.codex).
  PI_CONFIG_DIRS       Space-separated pi config dirs. Wins over PI_CODING_AGENT_DIR.
  PI_CODING_AGENT_DIR  Single pi config directory override (default: ~/.pi/agent).
                       With neither set, both personal and base dirs are linked.
  AGENT_HOSTS_ENV      Machine-local scope file (default: ~/.agents/hosts.env).
                       Sourced when present, so an argument-free --check knows
                       which dirs and hosts this machine actually uses.
  HARNESS_SKIP_HOSTS   Space-separated hosts to skip when --host is all.
                       An explicit --host always wins over this list.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)
      [ -z "$MODE" ] || { echo "Choose exactly one of --check or --apply." >&2; exit 2; }
      MODE="check"
      ;;
    --apply)
      [ -z "$MODE" ] || { echo "Choose exactly one of --check or --apply." >&2; exit 2; }
      MODE="apply"
      ;;
    --adopt)
      ADOPT=1
      ;;
    --host)
      shift
      [ "$#" -gt 0 ] || { echo "--host requires a value." >&2; exit 2; }
      HOST="$1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

[ -n "$MODE" ] || { echo "Choose --check or --apply." >&2; usage >&2; exit 2; }
[ "$ADOPT" -eq 0 ] || [ "$MODE" = "apply" ] || {
  echo "--adopt is valid only with --apply." >&2
  exit 2
}

case "$HOST" in
  all|claude|codex|pi|shared) ;;
  *) echo "Unknown host: $HOST" >&2; exit 2 ;;
esac

# A machine records its own host scope here so later runs do not re-derive it.
# The drift-check extension invokes this script with no arguments and no
# environment, so without this file it would rediscover the two-dir defaults
# and report permanent drift on dirs the machine never adopted. Entries use
# the := form, which leaves a real environment variable untouched.
SCOPE_FILE="${AGENT_HOSTS_ENV:-$HOME/.agents/hosts.env}"
if [ -f "$SCOPE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$SCOPE_FILE"
fi

if [ -n "${AGENT_CONFIG_REPO:-}" ]; then
  REPO="$AGENT_CONFIG_REPO"
elif [ -n "${CLAUDE_DOTFILES_REPO:-}" ]; then
  REPO="$CLAUDE_DOTFILES_REPO"
else
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  CANDIDATE=$(cd "$SCRIPT_DIR/.." && pwd)
  if [ -d "$CANDIDATE/.git" ] || git -C "$CANDIDATE" rev-parse --git-dir >/dev/null 2>&1; then
    REPO="$CANDIDATE"
  else
    REPO="$HOME/dev/personal/agent-config"
  fi
fi

if [ ! -d "$REPO" ]; then
  echo "Repo not found at $REPO." >&2
  echo "Set AGENT_CONFIG_REPO (or CLAUDE_DOTFILES_REPO) to override." >&2
  exit 1
fi
REPO=$(cd "$REPO" && pwd)

# Hosts keep their links for good, while worktree cleanup deletes worktrees,
# so a link must never point into a linked worktree. The script's own checkout
# resolves to its main checkout; an explicit override naming a worktree is a
# mistake worth stopping on.
REPO_COMMON=$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
REPO_GITDIR=$(git -C "$REPO" rev-parse --path-format=absolute --git-dir 2>/dev/null)
REPO_TOP=$(cd "$REPO" && git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$REPO_COMMON" ] && [ "$REPO_COMMON" != "$REPO_GITDIR" ] \
  && [ "$(cd "$REPO_TOP" 2>/dev/null && pwd -P)" = "$(cd "$REPO" && pwd -P)" ]; then
  MAIN_CHECKOUT=$(dirname "$REPO_COMMON")
  if [ -n "${AGENT_CONFIG_REPO:-}${CLAUDE_DOTFILES_REPO:-}" ]; then
    echo "Refusing to link hosts to the worktree $REPO." >&2
    echo "Worktree cleanup deletes it later. Point AGENT_CONFIG_REPO at the main checkout: $MAIN_CHECKOUT" >&2
    exit 1
  fi
  if [ "$(basename "$REPO_COMMON")" != ".git" ] || [ ! -d "$MAIN_CHECKOUT" ]; then
    echo "Refusing to link hosts to the worktree $REPO: its repo has no main checkout." >&2
    exit 1
  fi
  echo "Linking hosts to the main checkout $MAIN_CHECKOUT, not the worktree $REPO." >&2
  REPO=$(cd "$MAIN_CHECKOUT" && pwd)
fi

CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
SHARED_DIR="$HOME/.agents"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ISSUES=0

host_enabled() {
  if [ "$HOST" = "all" ]; then
    case " ${HARNESS_SKIP_HOSTS:-} " in
      *" $1 "*) return 1 ;;
    esac
    return 0
  fi
  [ "$HOST" = "$1" ]
}

report() {
  printf "%-34s %-13s %s\n" "$1" "$2" "$3"
}

mark_issue() {
  ISSUES=$((ISSUES + 1))
}

next_backup() {
  BACKUP_CANDIDATE="$1.bak.$TIMESTAMP"
  BACKUP_NUMBER=1
  while [ -e "$BACKUP_CANDIDATE" ] || [ -L "$BACKUP_CANDIDATE" ]; do
    BACKUP_CANDIDATE="$1.bak.$TIMESTAMP.$BACKUP_NUMBER"
    BACKUP_NUMBER=$((BACKUP_NUMBER + 1))
  done
  printf "%s\n" "$BACKUP_CANDIDATE"
}

home_tag() {
  case "$1" in
    "$HOME"/*) printf '~%s\n' "${1#"$HOME"}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

manage_link() {
  LABEL="$1"
  LIVE="$2"
  TARGET="$3"

  if [ ! -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
    report "$LABEL" "MISSING-SRC" "$TARGET"
    mark_issue
    return
  fi

  CONFLICT=""
  if [ -L "$LIVE" ]; then
    CURRENT=$(readlink "$LIVE")
    if [ "$CURRENT" = "$TARGET" ]; then
      report "$LABEL" "OK" "already correct"
      return
    fi
    CONFLICT="wrong link"
    CHECK_STATE="WRONG-LINK"
    CHECK_DETAIL="$CURRENT (expected $TARGET)"
  elif [ -e "$LIVE" ]; then
    CONFLICT="real path"
    CHECK_STATE="CONFLICT"
    CHECK_DETAIL="real path (requires --adopt)"
  fi

  if [ -n "$CONFLICT" ]; then
    if [ "$MODE" = "check" ]; then
      report "$LABEL" "$CHECK_STATE" "$CHECK_DETAIL"
      mark_issue
      return
    fi
    if [ "$ADOPT" -eq 0 ]; then
      report "$LABEL" "REFUSED" "$CONFLICT; re-run with --adopt"
      mark_issue
      return
    fi
    BACKUP=$(next_backup "$LIVE")
    if mv "$LIVE" "$BACKUP" && ln -s "$TARGET" "$LIVE"; then
      report "$LABEL" "ADOPTED" "backup: $BACKUP"
    else
      report "$LABEL" "FAILED" "could not back up and link"
      mark_issue
    fi
    return
  fi

  if [ "$MODE" = "check" ]; then
    report "$LABEL" "MISSING" "would link to $TARGET"
    mark_issue
    return
  fi

  if mkdir -p "$(dirname "$LIVE")" && ln -s "$TARGET" "$LIVE"; then
    report "$LABEL" "CREATED" "$TARGET"
  else
    report "$LABEL" "FAILED" "could not create link"
    mark_issue
  fi
}

refuse_config() {
  report "codex/config.toml" "REFUSED" "$1"
  mark_issue
}

# Sets KEY_STATE to none, root, table, or multi, and KEY_LINE to the match.
root_key_info() {
  KEY_LINE=$(awk -v key="$1" '
    /^[[:space:]]*\[/ { in_table=1 }
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { print (in_table ? "table:" : "root:") $0 }
  ' "$CONFIG")
  case "$(printf "%s\n" "$KEY_LINE" | awk 'NF { count++ } END { print count+0 }')" in
    0) KEY_STATE="none" ;;
    1) KEY_STATE="${KEY_LINE%%:*}" ;;
    *) KEY_STATE="multi" ;;
  esac
}

# Sets KEY_COUNT for KEY under [TABLE] or as root TABLE.KEY, KEY_LINE to the
# last match, TABLE_COUNT for [TABLE] headers, and NESTED when a [TABLE.x]
# header or root TABLE.x key exists.
table_key_info() {
  TABLE_INFO=$(awk -v t="$1" -v k="$2" '
    /^[[:space:]]*\[/ {
      seen_table=1
      in_t = ($0 ~ "^[[:space:]]*\\[" t "\\][[:space:]]*(#.*)?$")
      if (in_t) tables++
      if ($0 ~ "^[[:space:]]*\\[" t "[.]") nested=1
    }
    !seen_table && $0 ~ "^[[:space:]]*" t "[.]" { nested=1 }
    (!seen_table && $0 ~ "^[[:space:]]*" t "[.]" k "[[:space:]]*=") ||
      (in_t && $0 ~ "^[[:space:]]*" k "[[:space:]]*=") { keys++; line=$0 }
    END { print keys+0, tables+0, nested+0, line }
  ' "$CONFIG")
  read -r KEY_COUNT TABLE_COUNT NESTED KEY_LINE <<<"$TABLE_INFO"
}

manage_codex_config() {
  CONFIG="$CODEX_DIR/config.toml"
  FALLBACK='project_doc_fallback_filenames = ["CLAUDE.md"]'
  CONTEXT_WINDOW='model_context_window = 1050000'
  COMPACT_LIMIT='model_auto_compact_token_limit = 950000'
  STATUS_LINE='status_line = ["project-name", "git-branch", "model-with-reasoning", "context-used", "five-hour-limit", "weekly-limit", "thread-credits", "estimated-thread-cost"]'
  FALLBACK_MANUAL="manually set TOML root: $FALLBACK"
  CONTEXT_MANUAL="manually set TOML root: $CONTEXT_WINDOW"
  COMPACT_MANUAL="manually set TOML root: $COMPACT_LIMIT"
  STATUS_MANUAL="manually set under [tui]: $STATUS_LINE"
  HOOKS_FEATURE='hooks = true'
  HOOKS_MANUAL="manually set under [features]: $HOOKS_FEATURE"
  ADD_FALLBACK=1
  ADD_CONTEXT=1
  ADD_COMPACT=1
  ADD_STATUS=1
  ADD_HOOKS=1

  if [ -L "$CONFIG" ] || { [ -e "$CONFIG" ] && [ ! -f "$CONFIG" ]; }; then
    refuse_config "must be a regular file; $FALLBACK_MANUAL"
    return
  fi

  if [ -f "$CONFIG" ]; then
    root_key_info project_doc_fallback_filenames
    case "$KEY_STATE" in
      multi) refuse_config "multiple fallback keys; $FALLBACK_MANUAL"; return ;;
      table) refuse_config "fallback is not at TOML root; $FALLBACK_MANUAL"; return ;;
      root)
        case "$KEY_LINE" in
          *'['*CLAUDE.md*']'*) ADD_FALLBACK=0 ;;
          *) refuse_config "fallback differs or is multiline; $FALLBACK_MANUAL"; return ;;
        esac
        ;;
    esac

    root_key_info model_context_window
    case "$KEY_STATE" in
      multi) refuse_config "multiple context-window keys; $CONTEXT_MANUAL"; return ;;
      table) refuse_config "context window is not at TOML root; $CONTEXT_MANUAL"; return ;;
      root) ADD_CONTEXT=0 ;;
    esac

    root_key_info model_auto_compact_token_limit
    case "$KEY_STATE" in
      multi) refuse_config "multiple auto-compact keys; $COMPACT_MANUAL"; return ;;
      table) refuse_config "auto-compact limit is not at TOML root; $COMPACT_MANUAL"; return ;;
      root) ADD_COMPACT=0 ;;
    esac

    table_key_info tui status_line
    if [ "$KEY_COUNT" -gt 1 ]; then
      refuse_config "multiple status lines; $STATUS_MANUAL"
      return
    elif [ "$KEY_COUNT" -eq 1 ]; then
      ADD_STATUS=0
    elif [ "$TABLE_COUNT" -gt 1 ]; then
      refuse_config "multiple [tui] tables; $STATUS_MANUAL"
      return
    elif [ "$TABLE_COUNT" -eq 0 ] && [ "$NESTED" -eq 1 ]; then
      refuse_config "nested or dotted tui config; $STATUS_MANUAL"
      return
    fi

    table_key_info features hooks
    if [ "$KEY_COUNT" -gt 1 ]; then
      refuse_config "multiple hooks feature keys; $HOOKS_MANUAL"
      return
    elif [ "$KEY_COUNT" -eq 1 ]; then
      if ! printf "%s\n" "$KEY_LINE" | grep -Eq '=[[:space:]]*true[[:space:]]*(#.*)?$'; then
        refuse_config "hooks feature is not true; $HOOKS_MANUAL"
        return
      fi
      ADD_HOOKS=0
    elif [ "$TABLE_COUNT" -gt 1 ]; then
      refuse_config "multiple [features] tables; $HOOKS_MANUAL"
      return
    elif [ "$TABLE_COUNT" -eq 0 ] && [ "$NESTED" -eq 1 ]; then
      refuse_config "nested or dotted features config; $HOOKS_MANUAL"
      return
    fi
  fi

  if [ "$ADD_FALLBACK" -eq 0 ] && [ "$ADD_CONTEXT" -eq 0 ] && [ "$ADD_COMPACT" -eq 0 ] && [ "$ADD_STATUS" -eq 0 ] && [ "$ADD_HOOKS" -eq 0 ]; then
    report "codex/config.toml" "OK" "managed defaults configured"
    return
  fi

  if [ "$MODE" = "check" ]; then
    while IFS='|' read -r ADD DETAIL; do
      [ "$ADD" -eq 1 ] || continue
      report "codex/config.toml" "MISSING" "$DETAIL"
      mark_issue
    done <<EOF
$ADD_FALLBACK|would add root fallback key
$ADD_CONTEXT|would add 1.05M context window
$ADD_COMPACT|would add long-context compaction limit
$ADD_STATUS|would add default status line
$ADD_HOOKS|would enable the hooks feature
EOF
    return
  fi

  if ! mkdir -p "$(dirname "$CONFIG")"; then
    report "codex/config.toml" "FAILED" "could not create parent directory"
    mark_issue
    return
  fi

  if [ -f "$CONFIG" ]; then
    CONFIG_BACKUP=$(next_backup "$CONFIG")
    if ! mv "$CONFIG" "$CONFIG_BACKUP"; then
      report "codex/config.toml" "FAILED" "could not create backup"
      mark_issue
      return
    fi
    PREPENDED_ROOT=$((ADD_FALLBACK + ADD_CONTEXT + ADD_COMPACT))
    if {
      if [ "$ADD_FALLBACK" -eq 1 ]; then
        printf "%s\n" "$FALLBACK"
      fi
      if [ "$ADD_CONTEXT" -eq 1 ]; then
        printf "%s\n" "$CONTEXT_WINDOW"
      fi
      if [ "$ADD_COMPACT" -eq 1 ]; then
        printf "%s\n" "$COMPACT_LIMIT"
      fi
      if [ "$PREPENDED_ROOT" -gt 0 ] && [ -s "$CONFIG_BACKUP" ]; then
        printf "\n"
      fi
      awk -v add_status="$ADD_STATUS" -v add_hooks="$ADD_HOOKS" -v prepended="$PREPENDED_ROOT" \
        -v status_line="$STATUS_LINE" -v hooks_feature="$HOOKS_FEATURE" '
        { print }
        add_status && $0 ~ /^[[:space:]]*\[tui\][[:space:]]*(#.*)?$/ {
          print status_line
          status_done=1
        }
        add_hooks && $0 ~ /^[[:space:]]*\[features\][[:space:]]*(#.*)?$/ {
          print hooks_feature
          hooks_done=1
        }
        END {
          written = NR > 0 || prepended
          if (add_status && !status_done) {
            if (written) print ""
            print "[tui]"
            print status_line
            written=1
          }
          if (add_hooks && !hooks_done) {
            if (written) print ""
            print "[features]"
            print hooks_feature
          }
        }
      ' "$CONFIG_BACKUP"
    } > "$CONFIG"; then
      CONFIG_CHANGE="added missing managed defaults"
      report "codex/config.toml" "UPDATED" "$CONFIG_CHANGE; backup: $CONFIG_BACKUP"
    else
      FAILED_COPY=$(next_backup "$CONFIG.failed")
      mv "$CONFIG" "$FAILED_COPY" 2>/dev/null || true
      mv "$CONFIG_BACKUP" "$CONFIG" 2>/dev/null || true
      report "codex/config.toml" "FAILED" "write failed; original restored if possible"
      mark_issue
    fi
  elif {
    printf "%s\n" "$FALLBACK"
    printf "%s\n" "$CONTEXT_WINDOW"
    printf "%s\n\n" "$COMPACT_LIMIT"
    printf "[tui]\n%s\n\n" "$STATUS_LINE"
    printf "[features]\n%s\n" "$HOOKS_FEATURE"
  } > "$CONFIG"; then
    report "codex/config.toml" "CREATED" "managed defaults"
  else
    report "codex/config.toml" "FAILED" "could not create config"
    mark_issue
  fi
}

# Codex gets one dispatcher entry per registry event instead of a copy of the
# registry: it runs every matching hook concurrently and has no `if` field, so
# ordering and filtering live in hooks/lib/dispatch.sh. A file whose commands
# all call this repo's dispatcher is ours and is regenerated when the registry
# changes; anything else is a user file and needs --adopt.
CODEX_HOOK_EVENTS='["PreToolUse", "PostToolUse", "SessionStart", "SessionEnd"]'

manage_codex_hooks() {
  HOOKS_FILE="$CODEX_DIR/hooks.json"
  DISPATCHER="$REPO/hooks/lib/dispatch.sh"
  TRUST_NOTE="review and trust it in Codex"

  if ! command -v jq >/dev/null 2>&1; then
    report "codex/hooks.json" "FAILED" "jq is required to read the hook registry"
    mark_issue
    return
  fi

  # The dispatcher runs an event's hooks in sequence, so its budget is the sum
  # of theirs, with Claude's 60-second default for a hook that sets none.
  if ! EXPECTED=$(jq --arg d "$DISPATCHER" --argjson events "$CODEX_HOOK_EVENTS" '
    (.hooks // {}) as $h
    | [$events[] | select(($h[.] // []) | length > 0)]
    | if length == 0 then empty else
        {hooks: (map({key: ., value: [{hooks: [{
          type: "command",
          command: (($d | @sh) + " " + .),
          timeout: ([$h[.][].hooks[]? | .timeout // 60] | add)
        }]}]}) | from_entries)}
      end
  ' "$REPO/settings.json" 2>/dev/null); then
    report "codex/hooks.json" "FAILED" "cannot parse $REPO/settings.json"
    mark_issue
    return
  fi

  if [ -z "$EXPECTED" ]; then
    report "codex/hooks.json" "OK" "registry has no Codex events"
    return
  fi
  if [ ! -x "$DISPATCHER" ]; then
    report "codex/hooks.json" "MISSING-SRC" "$DISPATCHER"
    mark_issue
    return
  fi
  if [ -L "$HOOKS_FILE" ] || { [ -e "$HOOKS_FILE" ] && [ ! -f "$HOOKS_FILE" ]; }; then
    report "codex/hooks.json" "REFUSED" "must be a regular file"
    mark_issue
    return
  fi

  HOOKS_STATE="missing"
  if [ -f "$HOOKS_FILE" ]; then
    if [ "$(jq -S . "$HOOKS_FILE" 2>/dev/null)" = "$(printf '%s\n' "$EXPECTED" | jq -S .)" ]; then
      report "codex/hooks.json" "OK" "dispatcher registered"
      return
    fi
    if jq -e --arg d "$DISPATCHER" '
      [.hooks[]?[]?.hooks[]?.command] | length > 0 and all(startswith($d | @sh))
    ' "$HOOKS_FILE" >/dev/null 2>&1; then
      HOOKS_STATE="stale"
    else
      HOOKS_STATE="foreign"
    fi
  fi

  if [ "$MODE" = "check" ]; then
    case "$HOOKS_STATE" in
      missing) report "codex/hooks.json" "MISSING" "would register the hook dispatcher" ;;
      stale) report "codex/hooks.json" "STALE" "registry events changed" ;;
      foreign) report "codex/hooks.json" "CONFLICT" "user hooks file (requires --adopt)" ;;
    esac
    mark_issue
    return
  fi
  if [ "$HOOKS_STATE" = "foreign" ] && [ "$ADOPT" -eq 0 ]; then
    report "codex/hooks.json" "REFUSED" "user hooks file; re-run with --adopt"
    mark_issue
    return
  fi

  HOOKS_DETAIL="$TRUST_NOTE"
  if [ "$HOOKS_STATE" != "missing" ]; then
    HOOKS_BACKUP=$(next_backup "$HOOKS_FILE")
    if ! mv "$HOOKS_FILE" "$HOOKS_BACKUP"; then
      report "codex/hooks.json" "FAILED" "could not create backup"
      mark_issue
      return
    fi
    HOOKS_DETAIL="$TRUST_NOTE; backup: $HOOKS_BACKUP"
  fi
  if mkdir -p "$(dirname "$HOOKS_FILE")" && printf '%s\n' "$EXPECTED" > "$HOOKS_FILE"; then
    case "$HOOKS_STATE" in
      missing) report "codex/hooks.json" "CREATED" "$HOOKS_DETAIL" ;;
      stale) report "codex/hooks.json" "UPDATED" "$HOOKS_DETAIL" ;;
      foreign) report "codex/hooks.json" "ADOPTED" "$HOOKS_DETAIL" ;;
    esac
  else
    report "codex/hooks.json" "FAILED" "could not write hooks file"
    mark_issue
  fi
}

printf "%-34s %-13s %s\n" "PATH" "STATE" "DETAIL"
printf "%-34s %-13s %s\n" "----" "-----" "------"

# Pi links every configured agent dir. Explicit: PI_CONFIG_DIRS (whitespace
# separated list). Compatibility: PI_CODING_AGENT_DIR (single dir). Default:
# the base dir plus the personal-account dir the account-switcher shim uses.
if [ -n "${PI_CONFIG_DIRS:-}" ]; then
  PI_DIRS="$PI_CONFIG_DIRS"
elif [ -n "${PI_CODING_AGENT_DIR:-}" ]; then
  PI_DIRS="$PI_CODING_AGENT_DIR"
else
  PI_DIRS="$HOME/.pi/agent $HOME/.pi-personal/agent"
fi

# Claude links every configured config dir. Explicit: CLAUDE_CONFIG_DIRS
# (space-separated list). Compatibility: CLAUDE_CONFIG_DIR links one dir.
# Default: the base dir plus the personal-account dir.
if [ -n "${CLAUDE_CONFIG_DIRS:-}" ]; then
  CLAUDE_DIRS="$CLAUDE_CONFIG_DIRS"
elif [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  CLAUDE_DIRS="$CLAUDE_CONFIG_DIR"
else
  CLAUDE_DIRS="$HOME/.claude $HOME/.claude-personal"
fi

# Claude Code reads AGENTS.md only at project level, so the user-level
# CLAUDE.md slot carries it. Always-loaded rules come from the linked rules/.
if host_enabled claude; then
  for CLAUDE_DIR in $CLAUDE_DIRS; do
    TAG=$(home_tag "$CLAUDE_DIR")
    while IFS='|' read -r NAME RELATIVE; do
      [ -n "$NAME" ] || continue
      manage_link "$TAG/$NAME" "$CLAUDE_DIR/$NAME" "$REPO/$RELATIVE"
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
  done
fi

if host_enabled codex; then
  manage_link "codex/AGENTS.md" "$CODEX_DIR/AGENTS.md" "$REPO/AGENTS.md"
  manage_codex_config
  manage_codex_hooks
fi

if host_enabled pi; then
  for PI_DIR in $PI_DIRS; do
    TAG=$(home_tag "$PI_DIR")
    manage_link "$TAG/AGENTS.md" "$PI_DIR/AGENTS.md" "$REPO/AGENTS.md"
    manage_link "$TAG/extensions" "$PI_DIR/extensions" "$REPO/pi/extensions"
    manage_link "$TAG/settings.json" "$PI_DIR/settings.json" "$REPO/pi/settings.json"
    manage_link "$TAG/models.json" "$PI_DIR/models.json" "$REPO/pi/models.json"
    manage_link "$TAG/mcp.json" "$PI_DIR/mcp.json" "$REPO/pi/mcp.json"
    manage_link "$TAG/agents" "$PI_DIR/agents" "$REPO/agents"
  done
fi

# ~/.agents is the host-neutral root. Shared skills, rules-adjacent resources
# and personas resolve there on every host, so a shared skill can name one
# path instead of a Claude-specific one that Codex and Pi never see. An
# explicit --host always gets these, including --host claude; only the
# argument-free --host all defers to the machine scope file.
if host_enabled shared || [ "$HOST" != "all" ]; then
  while IFS='|' read -r NAME RELATIVE; do
    [ -n "$NAME" ] || continue
    manage_link "shared/$NAME" "$SHARED_DIR/$NAME" "$REPO/$RELATIVE"
  done <<'EOF'
skills|skills
rules|rules
scripts|scripts
templates|templates
references|references
agents|agents
pull_request_template.md|.github/pull_request_template.md
EOF
fi

echo ""
if [ "$ISSUES" -eq 0 ]; then
  if [ "$MODE" = "check" ]; then
    echo "All selected host configuration is current."
  else
    echo "All selected host configuration is in place. Repo: $REPO"
  fi
  exit 0
fi

echo "$ISSUES selected configuration issue(s) remain." >&2
exit 1
