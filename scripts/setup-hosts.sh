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

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
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

ensure_parent() {
  PARENT=$(dirname "$1")
  if [ -d "$PARENT" ]; then
    return 0
  fi
  mkdir -p "$PARENT"
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

  if [ -L "$LIVE" ]; then
    CURRENT=$(readlink "$LIVE")
    if [ "$CURRENT" = "$TARGET" ]; then
      report "$LABEL" "OK" "already correct"
      return
    fi
    if [ "$MODE" = "check" ]; then
      report "$LABEL" "WRONG-LINK" "$CURRENT (expected $TARGET)"
      mark_issue
      return
    fi
    if [ "$ADOPT" -eq 0 ]; then
      report "$LABEL" "REFUSED" "wrong link; re-run with --adopt"
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

  if [ -e "$LIVE" ]; then
    if [ "$MODE" = "check" ]; then
      report "$LABEL" "CONFLICT" "real path (requires --adopt)"
      mark_issue
      return
    fi
    if [ "$ADOPT" -eq 0 ]; then
      report "$LABEL" "REFUSED" "real path; re-run with --adopt"
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

  if ensure_parent "$LIVE" && ln -s "$TARGET" "$LIVE"; then
    report "$LABEL" "CREATED" "$TARGET"
  else
    report "$LABEL" "FAILED" "could not create link"
    mark_issue
  fi
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
  ADD_FALLBACK=1
  ADD_CONTEXT=1
  ADD_COMPACT=1
  ADD_STATUS=1
  TUI_COUNT=0

  if [ -L "$CONFIG" ] || { [ -e "$CONFIG" ] && [ ! -f "$CONFIG" ]; }; then
    report "codex/config.toml" "REFUSED" "must be a regular file; $FALLBACK_MANUAL"
    mark_issue
    return
  fi

  if [ -f "$CONFIG" ]; then
    KEY_INFO=$(awk '
      /^[[:space:]]*\[/ { in_table=1 }
      /^[[:space:]]*project_doc_fallback_filenames[[:space:]]*=/ {
        if (in_table) print "table:" $0; else print "root:" $0
      }
    ' "$CONFIG")
    KEY_COUNT=$(printf "%s\n" "$KEY_INFO" | awk 'NF { count++ } END { print count+0 }')

    if [ "$KEY_COUNT" -gt 1 ]; then
      report "codex/config.toml" "REFUSED" "multiple fallback keys; $FALLBACK_MANUAL"
      mark_issue
      return
    fi
    if [ "$KEY_COUNT" -eq 1 ]; then
      case "$KEY_INFO" in
        root:*'['*CLAUDE.md*']'*)
          ADD_FALLBACK=0
          ;;
        root:*)
          report "codex/config.toml" "REFUSED" "fallback differs or is multiline; $FALLBACK_MANUAL"
          mark_issue
          return
          ;;
        table:*)
          report "codex/config.toml" "REFUSED" "fallback is not at TOML root; $FALLBACK_MANUAL"
          mark_issue
          return
          ;;
      esac
    fi

    CONTEXT_INFO=$(awk '
      /^[[:space:]]*\[/ { in_table=1 }
      /^[[:space:]]*model_context_window[[:space:]]*=/ {
        if (in_table) print "table:" $0; else print "root:" $0
      }
    ' "$CONFIG")
    CONTEXT_COUNT=$(printf "%s\n" "$CONTEXT_INFO" | awk 'NF { count++ } END { print count+0 }')
    if [ "$CONTEXT_COUNT" -gt 1 ]; then
      report "codex/config.toml" "REFUSED" "multiple context-window keys; $CONTEXT_MANUAL"
      mark_issue
      return
    elif [ "$CONTEXT_COUNT" -eq 1 ]; then
      case "$CONTEXT_INFO" in
        root:*) ADD_CONTEXT=0 ;;
        table:*)
          report "codex/config.toml" "REFUSED" "context window is not at TOML root; $CONTEXT_MANUAL"
          mark_issue
          return
          ;;
      esac
    fi

    COMPACT_INFO=$(awk '
      /^[[:space:]]*\[/ { in_table=1 }
      /^[[:space:]]*model_auto_compact_token_limit[[:space:]]*=/ {
        if (in_table) print "table:" $0; else print "root:" $0
      }
    ' "$CONFIG")
    COMPACT_COUNT=$(printf "%s\n" "$COMPACT_INFO" | awk 'NF { count++ } END { print count+0 }')
    if [ "$COMPACT_COUNT" -gt 1 ]; then
      report "codex/config.toml" "REFUSED" "multiple auto-compact keys; $COMPACT_MANUAL"
      mark_issue
      return
    elif [ "$COMPACT_COUNT" -eq 1 ]; then
      case "$COMPACT_INFO" in
        root:*) ADD_COMPACT=0 ;;
        table:*)
          report "codex/config.toml" "REFUSED" "auto-compact limit is not at TOML root; $COMPACT_MANUAL"
          mark_issue
          return
          ;;
      esac
    fi

    STATUS_INFO=$(awk '
      /^[[:space:]]*\[/ {
        if (!seen_table) seen_table=1
        in_tui = ($0 ~ /^[[:space:]]*\[tui\][[:space:]]*(#.*)?$/)
      }
      !seen_table && /^[[:space:]]*tui[.]status_line[[:space:]]*=/ { print "root:" $0 }
      in_tui && /^[[:space:]]*status_line[[:space:]]*=/ { print "tui:" $0 }
    ' "$CONFIG")
    STATUS_COUNT=$(printf "%s\n" "$STATUS_INFO" | awk 'NF { count++ } END { print count+0 }')
    TUI_COUNT=$(awk '/^[[:space:]]*\[tui\][[:space:]]*(#.*)?$/ { count++ } END { print count+0 }' "$CONFIG")

    if [ "$STATUS_COUNT" -gt 1 ]; then
      report "codex/config.toml" "REFUSED" "multiple status lines; $STATUS_MANUAL"
      mark_issue
      return
    fi
    if [ "$STATUS_COUNT" -eq 1 ]; then
      ADD_STATUS=0
    elif [ "$TUI_COUNT" -gt 1 ]; then
      report "codex/config.toml" "REFUSED" "multiple [tui] tables; $STATUS_MANUAL"
      mark_issue
      return
    elif [ "$TUI_COUNT" -eq 0 ]; then
      TUI_AMBIGUOUS=$(awk '
        /^[[:space:]]*\[/ { seen_table=1 }
        /^[[:space:]]*\[tui[.]/ { found=1 }
        !seen_table && /^[[:space:]]*tui[.]/ { found=1 }
        END { print found+0 }
      ' "$CONFIG")
      if [ "$TUI_AMBIGUOUS" -eq 1 ]; then
        report "codex/config.toml" "REFUSED" "nested or dotted tui config; $STATUS_MANUAL"
        mark_issue
        return
      fi
    fi
  fi

  if [ "$ADD_FALLBACK" -eq 0 ] && [ "$ADD_CONTEXT" -eq 0 ] && [ "$ADD_COMPACT" -eq 0 ] && [ "$ADD_STATUS" -eq 0 ]; then
    report "codex/config.toml" "OK" "managed defaults configured"
    return
  fi

  if [ "$MODE" = "check" ]; then
    if [ "$ADD_FALLBACK" -eq 1 ]; then
      report "codex/config.toml" "MISSING" "would add root fallback key"
      mark_issue
    fi
    if [ "$ADD_CONTEXT" -eq 1 ]; then
      report "codex/config.toml" "MISSING" "would add 1.05M context window"
      mark_issue
    fi
    if [ "$ADD_COMPACT" -eq 1 ]; then
      report "codex/config.toml" "MISSING" "would add long-context compaction limit"
      mark_issue
    fi
    if [ "$ADD_STATUS" -eq 1 ]; then
      report "codex/config.toml" "MISSING" "would add default status line"
      mark_issue
    fi
    return
  fi

  if ! ensure_parent "$CONFIG"; then
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
      awk -v add_status="$ADD_STATUS" -v prepended="$PREPENDED_ROOT" -v status_line="$STATUS_LINE" '
        { print }
        add_status && $0 ~ /^[[:space:]]*\[tui\][[:space:]]*(#.*)?$/ {
          print status_line
          inserted=1
        }
        END {
          if (add_status && !inserted) {
            if (NR > 0 || prepended) print ""
            print "[tui]"
            print status_line
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
    printf "[tui]\n%s\n" "$STATUS_LINE"
  } > "$CONFIG"; then
    report "codex/config.toml" "CREATED" "managed defaults"
  else
    report "codex/config.toml" "FAILED" "could not create config"
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

if host_enabled claude; then
  for CLAUDE_DIR in $CLAUDE_DIRS; do
    TAG="$(printf %s "$CLAUDE_DIR" | sed "s#^$HOME#~#")"
    while IFS='|' read -r NAME RELATIVE; do
      [ -n "$NAME" ] || continue
      manage_link "$TAG/$NAME" "$CLAUDE_DIR/$NAME" "$REPO/$RELATIVE"
    done <<'EOF'
CLAUDE.md|CLAUDE.md
settings.json|settings.json
agents|agents
hooks|hooks
rules|rules
skills|skills
scripts|scripts
docs|docs
references|references
statusline.sh|scripts/statusline.sh
pull_request_template.md|.github/pull_request_template.md
EOF
  done
fi

if host_enabled codex; then
  manage_link "codex/AGENTS.md" "$CODEX_DIR/AGENTS.md" "$REPO/AGENTS.md"
  manage_codex_config
fi

if host_enabled pi; then
  for PI_DIR in $PI_DIRS; do
    TAG="$PI_DIR"
    case "$TAG" in
      "$HOME"/*) TAG="~${TAG#"$HOME"}" ;;
    esac
    manage_link "$TAG/AGENTS.md" "$PI_DIR/AGENTS.md" "$REPO/AGENTS.md"
    manage_link "$TAG/extensions" "$PI_DIR/extensions" "$REPO/pi/extensions"
    manage_link "$TAG/settings.json" "$PI_DIR/settings.json" "$REPO/pi/settings.json"
    manage_link "$TAG/models.json" "$PI_DIR/models.json" "$REPO/pi/models.json"
    manage_link "$TAG/agents" "$PI_DIR/agents" "$REPO/agents"
  done
fi

if host_enabled shared || [ "$HOST" = "codex" ] || [ "$HOST" = "pi" ]; then
  manage_link "shared/skills" "$SHARED_DIR/skills" "$REPO/skills"
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
