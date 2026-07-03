#!/usr/bin/env bash
# Claude Code status line script

input=$(cat)

# --- Data extraction ---
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // "?"')
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')
output_style=$(echo "$input" | jq -r '.output_style.name // empty')
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
five_hour_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_day_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
cur_version=$(echo "$input" | jq -r '.version // empty')

# Thinking effort — not in statusline JSON; read from env or settings files (best-effort).
# Precedence: env → project .claude/settings.local.json → project .claude/settings.json → ~/.claude/settings.json
effort="${CLAUDE_CODE_EFFORT_LEVEL:-}"
if [ -z "$effort" ]; then
  for f in "$cwd/.claude/settings.local.json" "$cwd/.claude/settings.json" "$HOME/.claude/settings.json"; do
    if [ -f "$f" ]; then
      v=$(jq -r '.effortLevel // empty' "$f" 2>/dev/null)
      if [ -n "$v" ] && [ "$v" != "null" ]; then effort="$v"; break; fi
    fi
  done
fi

# Shorten path: prefer "repo[/subpath]" if inside a git repo; else "~/relative".
short_path=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
  repo_name=$(basename "$repo_root")
  if [ "$cwd" = "$repo_root" ]; then
    short_path="$repo_name"
  else
    rel="${cwd#$repo_root/}"
    short_path="$repo_name/$rel"
  fi
elif [[ "$cwd" == "$HOME"* ]]; then
  short_path="~${cwd#$HOME}"
else
  short_path="$cwd"
fi

# Git branch + status counts (untracked, unstaged, staged, ahead, behind)
branch=""
gs_untracked=0
gs_modified=0
gs_staged=0
gs_ahead=0
gs_behind=0
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  porcelain=$(git -C "$cwd" status --porcelain 2>/dev/null)
  if [ -n "$porcelain" ]; then
    while IFS= read -r line; do
      idx="${line:0:1}"   # staged (index)
      wt="${line:1:1}"    # unstaged (worktree)
      if [ "$idx$wt" = "??" ]; then
        gs_untracked=$((gs_untracked + 1))
      else
        case "$idx" in M|A|D|R|C) gs_staged=$((gs_staged + 1)) ;; esac
        case "$wt"  in M|D|U)     gs_modified=$((gs_modified + 1)) ;; esac
      fi
    done <<< "$porcelain"
  fi
  # Ahead/behind vs upstream — silent if no upstream configured
  ab=$(git -C "$cwd" rev-list --count --left-right '@{upstream}...HEAD' 2>/dev/null)
  if [ -n "$ab" ]; then
    gs_behind="${ab%%	*}"
    gs_ahead="${ab##*	}"
  fi
fi

# --- ANSI colors ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
DIM='\033[2m'
ITALIC='\033[3m'
RESET='\033[0m'

# --- Time-left helper ---
# Format seconds remaining until epoch $1 as a single unit: "45m", "1.4h", "3.2d".
time_left() {
  local target="$1"
  [ -z "$target" ] && return
  local now=$(date +%s)
  local secs=$(( target - now ))
  [ "$secs" -le 0 ] && { printf "0m"; return; }
  local tenths whole frac
  if [ "$secs" -ge 86400 ]; then
    tenths=$(( (secs * 10 + 43200) / 86400 ))   # rounded tenths of a day
    whole=$(( tenths / 10 )); frac=$(( tenths % 10 ))
    if [ "$frac" -eq 0 ]; then printf "%dd" "$whole"; else printf "%d.%dd" "$whole" "$frac"; fi
  elif [ "$secs" -ge 3600 ]; then
    tenths=$(( (secs * 10 + 1800) / 3600 ))     # rounded tenths of an hour
    whole=$(( tenths / 10 )); frac=$(( tenths % 10 ))
    if [ "$frac" -eq 0 ]; then printf "%dh" "$whole"; else printf "%d.%dh" "$whole" "$frac"; fi
  else
    printf "%dm" $(( (secs + 30) / 60 ))
  fi
}

# --- Progress bar helper ---
make_bar() {
  local pct="$1" label="$2" width="$3"
  local int filled color
  int=$(printf '%.0f' "$pct")
  [ "$int" -lt 0 ] && int=0
  [ "$int" -gt 100 ] && int=100
  filled=$(( int * width / 100 ))

  if   [ "$int" -lt 50 ]; then color="$GREEN"
  elif [ "$int" -lt 80 ]; then color="$YELLOW"
  else                         color="$RED"
  fi

  local bar="" i
  for ((i=0; i<width; i++)); do
    if [ "$i" -lt "$filled" ]; then bar+="█"; else bar+="░"; fi
  done

  printf "${DIM}%s${RESET}${color}%s${RESET}${DIM} %2d%%${RESET}" "$label" "$bar" "$int"
}

# --- New-version check (non-blocking, cached 1h) ---
# Background-refresh latest version from npm registry; statusline never blocks.
NPM_PKG="@anthropic-ai/claude-code"
LATEST_FILE="/tmp/claude-statusline-latest-version"
update_indicator=""

if [ -n "$cur_version" ]; then
  needs_refresh=1
  if [ -f "$LATEST_FILE" ]; then
    file_age=$(( $(date +%s) - $(stat -f %m "$LATEST_FILE" 2>/dev/null || stat -c %Y "$LATEST_FILE" 2>/dev/null || echo 0) ))
    [ "$file_age" -lt 3600 ] && needs_refresh=0
  fi
  if [ "$needs_refresh" = "1" ]; then
    ( curl -fsS --max-time 5 "https://registry.npmjs.org/${NPM_PKG}/latest" 2>/dev/null \
        | jq -r '.version // empty' > "${LATEST_FILE}.tmp" 2>/dev/null \
        && [ -s "${LATEST_FILE}.tmp" ] && mv "${LATEST_FILE}.tmp" "$LATEST_FILE"
    ) >/dev/null 2>&1 &
    disown 2>/dev/null
  fi
  if [ -s "$LATEST_FILE" ]; then
    latest=$(cat "$LATEST_FILE")
    # Simple semver compare via sort -V
    if [ -n "$latest" ] && [ "$latest" != "$cur_version" ]; then
      newer=$(printf "%s\n%s\n" "$cur_version" "$latest" | sort -V | tail -1)
      [ "$newer" = "$latest" ] && update_indicator="$latest"
    fi
  fi
fi

# --- Build status line (two lines) ---
bar_width=8
line1=()  # identity: path, branch, model, effort, output style, update
line2=()  # usage meters: ctx, 5h, 7d

# Line 1 — path
line1+=("$(printf "${CYAN} %s${RESET}" "$short_path")")

# Line 1 — git branch + Powerline-style status counts
if [ -n "$branch" ]; then
  status_str=""
  [ "$gs_untracked" -gt 0 ] && status_str+=$(printf " ${YELLOW}?%d${RESET}" "$gs_untracked")
  [ "$gs_modified"  -gt 0 ] && status_str+=$(printf " ${YELLOW}!%d${RESET}" "$gs_modified")
  [ "$gs_staged"    -gt 0 ] && status_str+=$(printf " ${GREEN}+%d${RESET}" "$gs_staged")
  [ "$gs_ahead"     -gt 0 ] && status_str+=$(printf " ${CYAN}↑%d${RESET}" "$gs_ahead")
  [ "$gs_behind"    -gt 0 ] && status_str+=$(printf " ${RED}↓%d${RESET}" "$gs_behind")
  line1+=("$(printf "${GREEN}󰘬 %s${RESET}%b" "$branch" "$status_str")")
fi

# Line 1 — model (drop any parenthetical context-window suffix)
model_base="${model%% (*}"
line1+=("$(printf "${DIM}󰚩 %s${RESET}" "$model_base")")

# Line 1 — thinking effort
if [ -n "$effort" ]; then
  case "$effort" in
    max|xhigh) effort_color="$MAGENTA" ;;
    high)      effort_color="$YELLOW" ;;
    medium)    effort_color="$GREEN" ;;
    low)       effort_color="$DIM" ;;
    *)         effort_color="$DIM" ;;
  esac
  line1+=("$(printf "${effort_color}󰧑 %s${RESET}" "$effort")")
fi

# Line 1 — output style
[ -n "$output_style" ] && [ "$output_style" != "default" ] && [ "$output_style" != "null" ] \
  && line1+=("$(printf "${YELLOW} %s${RESET}" "$output_style")")

# Line 1 — caveman badge
# Read "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active" safely. Refuse
# symlinks, cap to 64 bytes, whitelist known modes. Avoids terminal-escape
# injection via attacker-controlled flag contents.
caveman_flag="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active"
if [ -f "$caveman_flag" ] && [ ! -L "$caveman_flag" ]; then
  caveman_mode=$(head -c 64 "$caveman_flag" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
  CAVEMAN_ORANGE='\033[38;5;172m'
  CAVEMAN_RED='\033[38;5;160m'
  case "$caveman_mode" in
    off)
      line1+=("$(printf "${DIM}󰣪 off${RESET}")")
      ;;
    ultra|wenyan-ultra)
      line1+=("$(printf "${CAVEMAN_RED}󰣪 %s${RESET}" "$caveman_mode")")
      ;;
    full|lite|wenyan|wenyan-lite|wenyan-full|review|commit|compress)
      line1+=("$(printf "${CAVEMAN_ORANGE}󰣪 %s${RESET}" "$caveman_mode")")
      ;;
    *) ;;
  esac
fi

# Line 1 — update indicator
if [ -n "$update_indicator" ]; then
  line1+=("$(printf "${MAGENTA}%s⬆${RESET}" "$update_indicator")")
fi

# Line 2 — usage meters
[ -n "$ctx_pct" ] && line2+=("$(make_bar "$ctx_pct" " ctx " "$bar_width")")

if [ -n "$five_hour_pct" ]; then
  bar=$(make_bar "$five_hour_pct" " 5h " "$bar_width")
  left=$(time_left "$five_hour_reset")
  [ -n "$left" ] && bar+=$(printf " ${DIM}%s${RESET}" "$left")
  line2+=("$bar")
fi

if [ -n "$seven_day_pct" ]; then
  bar=$(make_bar "$seven_day_pct" " 7d " "$bar_width")
  left=$(time_left "$seven_day_reset")
  [ -n "$left" ] && bar+=$(printf " ${DIM}%s${RESET}" "$left")
  line2+=("$bar")
fi

# Join each line with spaces
join_parts() {
  local out=""
  for p in "$@"; do
    if [ -z "$out" ]; then out="$p"; else out="$out  $p"; fi
  done
  printf "%s" "$out"
}

l1=$(join_parts "${line1[@]}")
printf "%b\n" "$l1"
if [ ${#line2[@]} -gt 0 ]; then
  l2=$(join_parts "${line2[@]}")
  printf "%b\n" "$l2"
fi
