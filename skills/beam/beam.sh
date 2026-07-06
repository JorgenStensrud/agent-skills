#!/usr/bin/env bash
# beam.sh — teleport a Claude Code session between machines.
#
# Sessions are plain JSONL files under $CLAUDE_CONFIG_DIR/projects/<slug>/,
# where <slug> is the absolute cwd with every non-alphanumeric char replaced
# by '-'. Machines lay out projects differently, so machines.json maps each
# project name to its absolute path per machine; the slug is derived from
# that. Transfer is rsync-over-ssh of a single session file (+ its sidecar
# dir when present), so there is exactly one writer per file at any time.
#
# Usage:
#   beam.sh push <machine> [session-id]   send session to <machine>
#   beam.sh pull <machine> [session-id]   fetch session from <machine>
#   beam.sh list <machine>                list remote sessions for this project
#
# Without session-id: the most recently modified session for the current
# project is used. Refuses to overwrite a diverged target file unless
# --force is given (protects against losing progress made on the other side).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/machines.json"
LOCAL_PROJECTS="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
FORCE=0

die() { echo "beam: $*" >&2; exit 1; }

# --- arg parsing -------------------------------------------------------------
ARGS=()
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    *) ARGS+=("$a") ;;
  esac
done
VERB="${ARGS[0]:-}"
MACHINE="${ARGS[1]:-}"
SESSION="${ARGS[2]:-}"
[[ "$VERB" =~ ^(push|pull|list)$ ]] || die "usage: beam.sh push|pull|list <machine> [session-id] [--force]"
[[ -n "$MACHINE" ]] || die "missing <machine>"
[[ -f "$CONFIG" ]] || die "missing $CONFIG"

# --- config lookup (python for JSON) ----------------------------------------
cfg() { python3 -c "
import json,sys
d=json.load(open('$CONFIG'))
print(eval(sys.argv[1], {'d': d}) or '')
" "$1"; }

SSH_HOST=$(cfg "d['machines']['$MACHINE']['ssh']" 2>/dev/null) || die "unknown machine '$MACHINE' (see machines.json)"
REMOTE_HOME=$(cfg "d['machines']['$MACHINE']['home']")
[[ -n "$SSH_HOST" && "$SSH_HOST" != "None" ]] || die "'$MACHINE' has no ssh host (is it this machine?)"

# --- project + slug resolution -----------------------------------------------
PROJ_NAME=$(basename "$PWD")
LOCAL_ABS="$PWD"

remote_path_for_project() {
  local mapped
  mapped=$(cfg "d.get('projects',{}).get('$PROJ_NAME',{}).get('$MACHINE')")
  if [[ -z "$mapped" || "$mapped" == "None" ]]; then
    mapped=$(cfg "d['fallback']['$MACHINE']")
    mapped="${mapped/\{name\}/$PROJ_NAME}"
  fi
  echo "${mapped/#\~/$REMOTE_HOME}"
}

slugify() { echo "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

REMOTE_ABS=$(remote_path_for_project)
LOCAL_SLUG=$(slugify "$LOCAL_ABS")
REMOTE_SLUG=$(slugify "$REMOTE_ABS")
REMOTE_PROJECTS="$REMOTE_HOME/.claude/projects"
REMOTE_DIR="$REMOTE_PROJECTS/$REMOTE_SLUG"
LOCAL_DIR="$LOCAL_PROJECTS/$LOCAL_SLUG"

# --- helpers -------------------------------------------------------------
latest_local_session() {
  ls -t "$LOCAL_DIR"/*.jsonl 2>/dev/null | head -1 | xargs -n1 basename 2>/dev/null | sed 's/\.jsonl$//'
}
latest_remote_session() {
  ssh "$SSH_HOST" "ls -t '$REMOTE_DIR'/*.jsonl 2>/dev/null | head -1" | xargs -n1 basename 2>/dev/null | sed 's/\.jsonl$//'
}

check_divergence() { # $1=direction
  local lf="$LOCAL_DIR/$SESSION.jsonl" lsz rsz
  lsz=$(stat -f%z "$lf" 2>/dev/null || stat -c%s "$lf" 2>/dev/null || echo 0)
  rsz=$(ssh "$SSH_HOST" "stat -c%s '$REMOTE_DIR/$SESSION.jsonl' 2>/dev/null || stat -f%z '$REMOTE_DIR/$SESSION.jsonl' 2>/dev/null" || echo 0)
  [[ "$rsz" == "0" || -z "$rsz" ]] && return 0   # target absent → safe
  if [[ "$1" == push && "$rsz" -gt "$lsz" ]]; then
    [[ $FORCE == 1 ]] || die "remote copy is LARGER (resumed there?). Pull instead, or --force to overwrite."
  fi
  if [[ "$1" == pull && "$lsz" -gt "$rsz" ]]; then
    [[ $FORCE == 1 ]] || die "local copy is LARGER (resumed here?). Push instead, or --force to overwrite."
  fi
}

# --- verbs -------------------------------------------------------------------
case "$VERB" in
  list)
    echo "sessions on $MACHINE for $PROJ_NAME ($REMOTE_DIR):"
    ssh "$SSH_HOST" "ls -lt '$REMOTE_DIR'/*.jsonl 2>/dev/null" || echo "(none)"
    ;;

  push)
    [[ -n "$SESSION" ]] || SESSION=$(latest_local_session)
    [[ -n "$SESSION" ]] || die "no local sessions for $PROJ_NAME in $LOCAL_DIR"
    [[ -f "$LOCAL_DIR/$SESSION.jsonl" ]] || die "no such session: $SESSION"
    ssh "$SSH_HOST" "test -d '$REMOTE_ABS'" || echo "WARNING: $REMOTE_ABS missing on $MACHINE — resume needs that cwd (clone it first)." >&2
    check_divergence push
    ssh "$SSH_HOST" "mkdir -p '$REMOTE_DIR'"
    rsync -a "$LOCAL_DIR/$SESSION.jsonl" "$SSH_HOST:$REMOTE_DIR/"
    [[ -d "$LOCAL_DIR/$SESSION" ]] && rsync -a "$LOCAL_DIR/$SESSION/" "$SSH_HOST:$REMOTE_DIR/$SESSION/"
    echo "beamed $SESSION → $MACHINE"
    echo "on $MACHINE run:  cd $REMOTE_ABS && claude --resume $SESSION"
    echo "REMINDER: close the session on THIS machine before resuming there (single writer)."
    ;;

  pull)
    [[ -n "$SESSION" ]] || SESSION=$(latest_remote_session)
    [[ -n "$SESSION" ]] || die "no remote sessions for $PROJ_NAME in $REMOTE_DIR"
    check_divergence pull
    mkdir -p "$LOCAL_DIR"
    rsync -a "$SSH_HOST:$REMOTE_DIR/$SESSION.jsonl" "$LOCAL_DIR/"
    ssh "$SSH_HOST" "test -d '$REMOTE_DIR/$SESSION'" 2>/dev/null \
      && rsync -a "$SSH_HOST:$REMOTE_DIR/$SESSION/" "$LOCAL_DIR/$SESSION/" || true
    echo "fetched $SESSION ← $MACHINE"
    echo "run:  cd $LOCAL_ABS && claude --resume $SESSION"
    echo "REMINDER: make sure the session is closed on $MACHINE first (single writer)."
    ;;
esac
