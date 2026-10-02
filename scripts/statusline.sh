#!/bin/sh
# ANSI color codes
RESET='\033[0m'
BOLD='\033[1m'
CYAN='\033[36m'
YELLOW='\033[33m'
GREEN='\033[32m'
RED='\033[31m'
MAGENTA='\033[35m'
BLUE='\033[34m'
DIM='\033[2m'

# Dim delimiter drawn between every section
SEP=" ${DIM}│${RESET} "

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd')
folder=$(basename "$cwd")

# Git branch
branch=$(git -C "$cwd" -c core.hooksPath=/dev/null symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)

# Git dirty indicator: fast porcelain check, limit output to avoid slow large repos
if [ -n "$branch" ]; then
  dirty=$(git -C "$cwd" -c core.hooksPath=/dev/null status --porcelain 2>/dev/null | head -1)
  if [ -n "$dirty" ]; then
    git_color="$RED"
    git_marker="*"
  else
    git_color="$GREEN"
    git_marker=""
  fi
fi

# Node version: prefer .nvmrc (fast file read), fall back to node -v
node_version=""
if [ -f "$cwd/.nvmrc" ]; then
  node_version="v$(cat "$cwd/.nvmrc" | tr -d '[:space:]' | sed 's/^v//')"
elif command -v node >/dev/null 2>&1; then
  node_version=$(node -v 2>/dev/null)
fi

# Context: only present after first API call (current_usage non-null)
has_usage=$(echo "$input" | jq -r '.context_window.current_usage // empty')
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Compact a raw token number to e.g. "45.2k" or "999"
compact_tokens() {
  echo "$1" | awk '{
    if ($1 >= 1000) {
      val = $1 / 1000
      # One decimal place, strip trailing .0
      s = sprintf("%.1fk", val)
      sub(/\.0k$/, "k", s)
      print s
    } else {
      printf "%d", $1
    }
  }'
}

# Build output
printf "${BOLD}${CYAN}%s${RESET}" "$folder"

if [ -n "$branch" ]; then
  printf "${SEP}${DIM}on${RESET} ${git_color}%s%s${RESET}" "$branch" "$git_marker"
fi

if [ -n "$node_version" ]; then
  printf "${SEP}${BLUE}node${RESET} ${YELLOW}%s${RESET}" "$node_version"
fi

# Effort is absent when the model does not support the effort parameter
model=$(echo "$input" | jq -r '.model.display_name // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')
if [ -n "$model" ]; then
  printf "${SEP}${MAGENTA}%s${RESET}" "$model"
  if [ -n "$effort" ]; then
    printf " ${DIM}%s${RESET}" "$effort"
  fi
fi

# Context block: render from the start, defaulting to 0 before the first API call
if [ -n "$has_usage" ] && [ -n "$ctx_pct" ]; then
  pct_int=$(echo "$ctx_pct" | awk '{printf "%d", $1}')
  used_tokens=$(echo "$input" | jq -r '
    (.context_window.current_usage.input_tokens // 0)
    + (.context_window.current_usage.cache_read_input_tokens // 0)
    + (.context_window.current_usage.cache_creation_input_tokens // 0)
  ')
else
  pct_int=0
  used_tokens=0
fi

if [ "$pct_int" -ge 80 ]; then
  pct_color="$RED"
elif [ "$pct_int" -ge 50 ]; then
  pct_color="$YELLOW"
else
  pct_color="$GREEN"
fi

used_label=$(compact_tokens "$used_tokens")

printf "${SEP}${CYAN}context${RESET} ${pct_color}%s (%d%%)${RESET}" \
  "$used_label" "$pct_int"

# Plan usage vs rate limits: only present for Pro/Max after the first API response
five_h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# Pick a color for a usage percentage on the same thresholds as context
usage_color() {
  if [ "$1" -ge 80 ]; then
    printf '%s' "$RED"
  elif [ "$1" -ge 50 ]; then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$GREEN"
  fi
}

if [ -n "$five_h" ] || [ -n "$seven_d" ]; then
  printf "${SEP}${BOLD}${MAGENTA}usage${RESET}"
  if [ -n "$five_h" ]; then
    fh_int=$(echo "$five_h" | awk '{printf "%d", $1}')
    fh_color=$(usage_color "$fh_int")
    printf " 5h ${BOLD}${fh_color}%d%%${RESET}" "$fh_int"
  fi
  if [ -n "$seven_d" ]; then
    sd_int=$(echo "$seven_d" | awk '{printf "%d", $1}')
    sd_color=$(usage_color "$sd_int")
    printf " 7d ${BOLD}${sd_color}%d%%${RESET}" "$sd_int"
  fi
fi

# Minor currency units to a short label: $70.52 under $1000, $6.5k at or above.
compact_money() {
  echo "$1 $2" | awk '{
    div = 1
    for (i = 0; i < $2; i++) div *= 10
    major = $1 / div
    if (major >= 1000) {
      s = sprintf("$%.1fk", major / 1000)
      sub(/\.0k$/, "k", s)
      print s
    } else {
      printf "$%.2f", major
    }
  }'
}

# Severity is the server's own judgement of pool state, which matters when the pool is
# shared and local spend says nothing about how full it is. Its value set is not
# published, so anything unrecognised falls back to the local percentage thresholds.
credit_color() {
  case "$1" in
    normal) printf '%s' "$GREEN" ;;
    warning) printf '%s' "$YELLOW" ;;
    critical | exceeded | blocked) printf '%s' "$RED" ;;
    *) usage_color "$2" ;;
  esac
}

# Usage credits: the statusline payload carries no spend field, so read the client's own
# cached copy of the usage endpoint. Every field is nullable and the monthly cap is
# changed by admins, so none of it may be hardcoded.
cfg_json="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
credits=""
if [ -f "$cfg_json" ]; then
  credits=$(jq -r '
    (.cachedUsageUtilization // {}) as $c
    | ($c.utilization // {}) as $u
    | (($u.spend.used.amount_minor // $u.extra_usage.used_credits) // -1) as $used
    | (($u.spend.limit.amount_minor // $u.extra_usage.monthly_limit) // -1) as $limit
    | if $used < 0 or $limit <= 0 then empty
      else [$used, $limit, ($u.spend.used.exponent // 2), ($u.spend.severity // ""), ($c.fetchedAtMs // 0)] | @tsv
      end
  ' "$cfg_json" 2>/dev/null)
fi

if [ -n "$credits" ]; then
  used_minor=$(echo "$credits" | cut -f1)
  limit_minor=$(echo "$credits" | cut -f2)
  cred_exp=$(echo "$credits" | cut -f3)
  cred_sev=$(echo "$credits" | cut -f4)
  fetched_ms=$(echo "$credits" | cut -f5)

  now_s=$(date +%s)
  age_s=-1
  if [ "$fetched_ms" -gt 0 ]; then
    age_s=$((now_s - fetched_ms / 1000))
  fi

  # The client refreshes this cache only on its own triggers, so a long session renders a
  # figure that can be hours old. Ask Claude Code to refresh it under its own credentials:
  # those tokens rotate, and a second writer to the keychain risks signing the user out.
  # The stamp is written before spawning because renders fire many times a second and
  # would otherwise stampede the refresh window.
  if [ "$age_s" -lt 0 ] || [ "$age_s" -gt 300 ]; then
    stamp="${TMPDIR:-/tmp}/claude-statusline-usage-refresh-$(id -u)"
    if [ ! -f "$stamp" ] || [ -z "$(find "$stamp" -mmin -5 2>/dev/null)" ]; then
      : > "$stamp"
      claude_bin=$(command -v claude 2>/dev/null)
      if [ -n "$claude_bin" ]; then
        nohup "$claude_bin" -p /usage --strict-mcp-config \
          --mcp-config '{"mcpServers":{}}' >/dev/null 2>&1 &
      fi
    fi
  fi

  used_label=$(compact_money "$used_minor" "$cred_exp")
  limit_label=$(compact_money "$limit_minor" "$cred_exp")
  cred_pct=$(echo "$used_minor $limit_minor" | awk '{
    p = $1 * 100 / $2
    if (p > 0 && p < 0.1) { print "<0.1"; next }
    s = sprintf("%.1f", p)
    sub(/\.0$/, "", s)
    print s
  }')

  stale=""
  if [ "$age_s" -ge 900 ]; then
    age_min=$((age_s / 60))
    if [ "$age_min" -ge 60 ]; then
      stale=" · $((age_min / 60))h"
    else
      stale=" · ${age_min}m"
    fi
  fi

  if [ -n "$stale" ]; then
    printf "${SEP}${DIM}credits %s / %s (%s%%)%s${RESET}" \
      "$used_label" "$limit_label" "$cred_pct" "$stale"
  else
    cred_pct_int=$(echo "$used_minor $limit_minor" | awk '{printf "%d", $1 * 100 / $2}')
    cred_color=$(credit_color "$cred_sev" "$cred_pct_int")
    printf "${SEP}${BOLD}${MAGENTA}credits${RESET} ${cred_color}%s / %s (%s%%)${RESET}" \
      "$used_label" "$limit_label" "$cred_pct"
  fi
fi
