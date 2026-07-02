#!/usr/bin/env bash
# handoff.sh — unified dispatcher for cursor-agent, codex, and claude backends.
#
# Verbs: dispatch | list | status | cancel | resume | takeover
# State lives repo-locally under `<cwd>/.handoffs/<task_id>/`.
# All state.json read/write is delegated to `scripts/state.py`.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATE_PY="$SCRIPT_DIR/state.py"
PY=python3

die() { printf '%s\n' "$*" >&2; exit 1; }
warn() { printf '%s\n' "$*" >&2; }

# ---------- helpers ----------------------------------------------------------

iso_now() { date -u +"%Y-%m-%dT%H:%M:%S+00:00"; }

slugify() {
  # First 5 words of the input, lowercased, non-alnum -> dash, collapsed.
  local raw="$1"
  printf '%s' "$raw" \
    | awk '{ for (i=1;i<=5 && i<=NF;i++) printf "%s%s", $i, (i==5||i==NF?"":" ") }' \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E -e 's/[^a-z0-9]+/-/g' -e 's/^-+//' -e 's/-+$//' \
    | cut -c1-40
}

ensure_gitignore() {
  local root="$1"
  local gi="$root/.gitignore"
  if [[ ! -f "$gi" ]]; then
    printf ".handoffs/\n" > "$gi"
    warn "handoff: created $gi with .handoffs/ entry"
    return
  fi
  if grep -qE '^\.handoffs/?$' "$gi"; then
    return
  fi
  printf '\n.handoffs/\n' >> "$gi"
  warn "handoff: appended .handoffs/ to $gi"
}

pick_task_id() {
  local base="$1" root="$2"
  local day; day="$(date -u +%Y%m%d)"
  local id="${day}-${base}"
  local i=2
  while [[ -d "$root/.handoffs/$id" ]]; do
    id="${day}-${base}-${i}"
    i=$((i + 1))
  done
  printf '%s' "$id"
}

uuid4() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    "$PY" -c 'import uuid;print(uuid.uuid4())'
  fi
}

pid_lstart() {
  # macOS + Linux both accept `ps -o lstart= -p PID`.
  ps -o lstart= -p "$1" 2>/dev/null | sed -e 's/^ *//' -e 's/ *$//'
}

pid_alive() { kill -0 "$1" 2>/dev/null; }

json_emit() {
  # Emit a JSON object from key=value pairs, safely escaping strings.
  # Values prefixed with `int:` are emitted as JSON numbers, everything else as strings.
  "$PY" - "$@" <<'PY'
import json, sys
out = {}
for arg in sys.argv[1:]:
    k, _, v = arg.partition("=")
    if v.startswith("int:"):
        try:
            out[k] = int(v[4:])
        except ValueError:
            out[k] = None
    else:
        out[k] = v
print(json.dumps(out))
PY
}

# ---------- backend command construction -------------------------------------

build_cmd_dispatch() {
  # $1=backend, $2=session_id, $3=model, $4=task, $5=workspace
  local backend="$1" sid="$2" model="$3" task="$4" workspace="$5"
  case "$backend" in
    cursor-agent)
      local m=()
      [[ -n "$model" ]] && m=(--model "$model")
      printf 'cd %q && cursor-agent -p --resume %q --output-format stream-json --trust --yolo' "$workspace" "$sid"
      for x in "${m[@]}"; do printf ' %q' "$x"; done
      printf ' -- %q' "$task"
      ;;
    codex)
      local m=()
      [[ -n "$model" ]] && m=(--model "$model")
      printf 'cd %q && codex exec --json --skip-git-repo-check -s workspace-write' "$workspace"
      for x in "${m[@]}"; do printf ' %q' "$x"; done
      printf ' -- %q' "$task"
      ;;
    claude)
      local m=()
      [[ -n "$model" ]] && m=(--model "$model")
      printf 'cd %q && claude -p --output-format stream-json --verbose --dangerously-skip-permissions --session-id %q' "$workspace" "$sid"
      for x in "${m[@]}"; do printf ' %q' "$x"; done
      printf ' -- %q' "$task"
      ;;
    *) die "unknown backend: $backend" ;;
  esac
}

# ---------- verbs ------------------------------------------------------------

verb_dispatch() {
  local backend="" task="" slug="" model="" worktree=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --backend) backend="$2"; shift 2;;
      --task) task="$2"; shift 2;;
      --slug) slug="$2"; shift 2;;
      --model) model="$2"; shift 2;;
      --worktree) worktree=1; shift;;
      -h|--help) printf 'usage: handoff dispatch --backend {cursor|codex|claude} --task "<prompt>" [--slug <slug>] [--model <id>] [--worktree]\n'; return 0;;
      *) die "dispatch: unknown arg $1";;
    esac
  done
  [[ -n "$backend" ]] || die "dispatch: --backend required"
  [[ -n "$task" ]] || die "dispatch: --task required"
  case "$backend" in cursor) backend=cursor-agent;; cursor-agent|codex|claude) :;; *) die "dispatch: bad backend $backend";; esac

  local workspace; workspace="$(pwd)"
  [[ "$workspace" = /* ]] || die "dispatch: cwd is not absolute (?)"
  [[ -w "$workspace" ]] || die "dispatch: cwd not writable"

  if [[ "$worktree" -eq 1 ]]; then
    warn "handoff: --worktree flag noted; caller is expected to already be inside the desired worktree (skill does not create one)"
  fi

  [[ -n "$slug" ]] || slug="$(slugify "$task")"
  [[ -n "$slug" ]] || slug="task"
  local task_id; task_id="$(pick_task_id "$slug" "$workspace")"
  local task_dir="$workspace/.handoffs/$task_id"
  mkdir -p "$task_dir"

  ensure_gitignore "$workspace"

  local sid=""
  case "$backend" in
    cursor-agent)
      if ! command -v cursor-agent >/dev/null 2>&1; then
        die "cursor-agent not found on PATH"
      fi
      sid="$(cursor-agent create-chat 2>/dev/null | tr -d '[:space:]' || true)"
      if [[ -z "$sid" ]]; then
        die "refusing to start untracked run (cursor-agent create-chat failed)"
      fi
      ;;
    claude)
      command -v claude >/dev/null 2>&1 || die "claude CLI not found on PATH"
      sid="$(uuid4)"
      ;;
    codex)
      command -v codex >/dev/null 2>&1 || die "codex CLI not found on PATH"
      sid=""
      ;;
  esac

  local cmd; cmd="$(build_cmd_dispatch "$backend" "$sid" "$model" "$task" "$workspace")"

  "$PY" "$STATE_PY" init \
    --task-dir "$task_dir" \
    --task-id "$task_id" \
    --backend "$backend" \
    --session-id "$sid" \
    --task "$task" \
    --workspace "$workspace" \
    --model "$model" \
    --command "$cmd" >/dev/null

  local log="$task_dir/attempt-1.log"
  # Launch detached. Use setsid if available so the child survives shell exit.
  local launcher=(nohup)
  if command -v setsid >/dev/null 2>&1; then launcher=(setsid); fi
  ( "${launcher[@]}" bash -c "$cmd" >"$log" 2>&1 ) &
  local pid=$!
  disown "$pid" 2>/dev/null || true
  # Give the process a moment to actually spawn so lstart is stable.
  sleep 0
  local lstart; lstart="$(pid_lstart "$pid" || true)"

  "$PY" "$STATE_PY" set --task-dir "$task_dir" \
    "attempts[-1].pid=$pid" \
    "attempts[-1].pid_start=$lstart" >/dev/null

  json_emit \
    "task_id=$task_id" \
    "backend=$backend" \
    "session_id=$sid" \
    "pid=int:$pid" \
    "log=$log"
}

verb_list() {
  local as_json=0 status="" safe=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) as_json=1; shift;;
      --status) status="$2"; shift 2;;
      --safe) safe=1; shift;;
      -h|--help) printf 'usage: handoff list [--json] [--status <s>] [--safe]\n'; return 0;;
      *) die "list: unknown arg $1";;
    esac
  done
  local root; root="$(pwd)"
  local json
  if [[ -n "$status" ]]; then
    json="$("$PY" "$STATE_PY" list --root "$root" --status "$status")"
  else
    json="$("$PY" "$STATE_PY" list --root "$root")"
  fi
  if [[ "$as_json" -eq 1 ]]; then
    if [[ "$safe" -eq 1 ]]; then
      printf '%s\n' "$json" | "$PY" "$STATE_PY" redact
    else
      printf '%s\n' "$json"
    fi
    return 0
  fi
  local tbl
  tbl="$("$PY" - "$json" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
if not data:
    print("(no handoffs)")
    sys.exit(0)
fmt = "{:<28} {:<12} {:<10} {:<10} {:<25} {}"
print(fmt.format("task_id","backend","status","session","updated_at","task"))
print(fmt.format("-"*28,"-"*12,"-"*10,"-"*10,"-"*25,"-"*40))
for s in data:
    sid = (s.get("session_id") or "-")[:8]
    task = (s.get("task") or "").splitlines()[0][:60]
    print(fmt.format(
        s.get("task_id","?"),
        s.get("backend","?"),
        s.get("status","?"),
        sid,
        s.get("updated_at","?"),
        task,
    ))
PY
  )"
  if [[ "$safe" -eq 1 ]]; then
    printf '%s\n' "$tbl" | "$PY" "$STATE_PY" redact
  else
    printf '%s\n' "$tbl"
  fi
}

verb_status() {
  local safe=0
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --safe) safe=1; shift;;
      -h|--help) printf 'usage: handoff status <task_id> [--safe]\n'; return 0;;
      *) args+=("$1"); shift;;
    esac
  done
  set -- "${args[@]}"
  local id="${1:-}"; [[ -n "$id" ]] || die "usage: handoff status <task_id> [--safe]"
  local root; root="$(pwd)"
  local dir="$root/.handoffs/$id"
  [[ -d "$dir" ]] || die "no such task: $id"
  "$PY" "$STATE_PY" reconcile --task-dir "$dir" >/dev/null
  local out=""
  out+="$(cat "$dir/handoff.md")"
  out+=$'\n\n--- last log tail (40 lines) ---\n'
  # Find newest attempt log by numeric N (attempt-10 > attempt-2). Portable —
  # no reliance on GNU sort -k, since the enclosing path may contain dashes.
  local latest="" max=0 n
  local f
  for f in "$dir"/attempt-*.log; do
    [[ -e "$f" ]] || continue
    n="${f##*/attempt-}"; n="${n%.log}"
    if [[ "$n" =~ ^[0-9]+$ ]] && (( n > max )); then
      max=$n
      latest=$f
    fi
  done
  if [[ -n "$latest" ]]; then
    out+="($latest)"$'\n'
    out+="$(tail -n 40 "$latest" 2>/dev/null || true)"
  else
    out+="(no attempt logs)"
  fi
  if [[ "$safe" -eq 1 ]]; then
    printf '%s\n' "$out" | "$PY" "$STATE_PY" redact
  else
    printf '%s\n' "$out"
  fi
}

verb_cancel() {
  local id="${1:-}"; [[ -n "$id" ]] || die "usage: handoff cancel <task_id>"
  local root; root="$(pwd)"
  local dir="$root/.handoffs/$id"
  [[ -d "$dir" ]] || die "no such task: $id"
  # Reconcile first: if the process already died and the log carries a terminal
  # event, resolve to done/error rather than falsely stamping "cancelled".
  "$PY" "$STATE_PY" reconcile --task-dir "$dir" >/dev/null
  local status; status="$("$PY" "$STATE_PY" get --task-dir "$dir" status)"
  [[ "$status" == "running" ]] || die "not running (status=$status)"

  local pid; pid="$("$PY" "$STATE_PY" get --task-dir "$dir" 'attempts[-1].pid')"
  [[ "$pid" != "null" && -n "$pid" ]] || die "no pid recorded on last attempt"
  local stored_lstart; stored_lstart="$("$PY" "$STATE_PY" get --task-dir "$dir" 'attempts[-1].pid_start' 2>/dev/null || true)"
  # `get` prints raw string for strings; normalise "null" to empty.
  [[ "$stored_lstart" == "null" ]] && stored_lstart=""
  local cur_lstart; cur_lstart="$(pid_lstart "$pid" || true)"
  if [[ -n "$stored_lstart" && -n "$cur_lstart" && "$stored_lstart" != "$cur_lstart" ]]; then
    die "refusing to kill: pid $pid start-time changed ($stored_lstart -> $cur_lstart); likely recycled"
  fi

  if pid_alive "$pid"; then
    kill -TERM "$pid" 2>/dev/null || true
    local i=0
    while pid_alive "$pid" && [[ $i -lt 10 ]]; do sleep 0.5; i=$((i+1)); done
    if pid_alive "$pid"; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi

  "$PY" "$STATE_PY" set --task-dir "$dir" \
    status=cancelled \
    "attempts[-1].ended_at=$(iso_now)" \
    "attempts[-1].exit_code=-15" >/dev/null
  printf 'cancelled %s (pid=%s)\n' "$id" "$pid"
}

verb_resume() {
  local id="${1:-}"; [[ -n "$id" ]] || die "usage: handoff resume <task_id> [--task \"<additional>\"]"
  shift || true
  local extra=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task) extra="$2"; shift 2;;
      -h|--help) printf 'usage: handoff resume <task_id> [--task "<additional>"]\n'; return 0;;
      *) die "resume: unknown arg $1";;
    esac
  done
  local root; root="$(pwd)"
  local dir="$root/.handoffs/$id"
  [[ -d "$dir" ]] || die "no such task: $id"
  "$PY" "$STATE_PY" reconcile --task-dir "$dir" >/dev/null
  local status backend sid workspace model task
  status="$("$PY" "$STATE_PY" get --task-dir "$dir" status)"
  backend="$("$PY" "$STATE_PY" get --task-dir "$dir" backend)"
  sid="$("$PY" "$STATE_PY" get --task-dir "$dir" session_id 2>/dev/null || true)"
  workspace="$("$PY" "$STATE_PY" get --task-dir "$dir" workspace)"
  model="$("$PY" "$STATE_PY" get --task-dir "$dir" model 2>/dev/null || true)"
  [[ "$model" == "null" ]] && model=""
  task="$("$PY" "$STATE_PY" get --task-dir "$dir" task)"

  case "$status" in
    running|cancelled) die "refuse to resume: status=$status";;
  esac
  if [[ "$backend" == "codex" ]]; then
    die "codex resume is not implemented in this skill; use the codex-plugin /rescue. The takeover prompt is at $dir/handoff.md"
  fi
  [[ -n "$sid" && "$sid" != "null" ]] || die "no session id on file"

  local prompt="$task"
  [[ -n "$extra" ]] && prompt+=$'\n\n---\nFollow-up: '"$extra"

  # Compute next attempt N by counting existing attempt logs.
  local n
  n="$(ls -1 "$dir"/attempt-*.log 2>/dev/null | wc -l | tr -d ' ')"
  n=$((n + 1))
  local log="$dir/attempt-$n.log"

  local cmd; cmd="$(build_cmd_dispatch "$backend" "$sid" "$model" "$prompt" "$workspace")"
  local started; started="$(iso_now)"

  # Append the new attempt via a small inline python (needs list mutation
  # that state.py's `set` deliberately doesn't expose).
  "$PY" - "$dir" "$n" "$started" "$log" "$cmd" <<'PY'
import json, os, sys
from pathlib import Path
task_dir = Path(sys.argv[1])
n = int(sys.argv[2])
started = sys.argv[3]
log = os.path.basename(sys.argv[4])
cmd = sys.argv[5]
sp = task_dir / "state.json"
state = json.loads(sp.read_text())
state.setdefault("attempts", []).append({
    "n": n,
    "started_at": started,
    "ended_at": None,
    "pid": None,
    "pid_start": None,
    "exit_code": None,
    "log": log,
})
state["status"] = "running"
state["command"] = cmd
tmp = sp.with_suffix(".json.tmp")
tmp.write_text(json.dumps(state, indent=2) + "\n")
os.replace(tmp, sp)
PY

  local launcher=(nohup)
  if command -v setsid >/dev/null 2>&1; then launcher=(setsid); fi
  ( "${launcher[@]}" bash -c "$cmd" >"$log" 2>&1 ) &
  local pid=$!
  disown "$pid" 2>/dev/null || true
  local lstart; lstart="$(pid_lstart "$pid" || true)"

  "$PY" "$STATE_PY" set --task-dir "$dir" \
    "attempts[-1].pid=$pid" \
    "attempts[-1].pid_start=$lstart" >/dev/null

  json_emit \
    "task_id=$id" \
    "attempt=int:$n" \
    "pid=int:$pid" \
    "log=$log"
}

verb_takeover() {
  local id="${1:-}"; [[ -n "$id" ]] || die "usage: handoff takeover <task_id> [--exec] [--raw]"
  shift || true
  local do_exec=0 raw=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --exec) do_exec=1; shift;;
      --raw) raw=1; shift;;
      -h|--help) printf 'usage: handoff takeover <task_id> [--exec] [--raw]\n\nPrints the takeover prompt (default: redacted for safe paste elsewhere).\n--raw skips redaction. --exec launches the backend interactively instead.\n'; return 0;;
      *) die "takeover: unknown arg $1";;
    esac
  done
  local root; root="$(pwd)"
  local dir="$root/.handoffs/$id"
  [[ -d "$dir" ]] || die "no such task: $id"
  local backend sid
  backend="$("$PY" "$STATE_PY" get --task-dir "$dir" backend)"
  sid="$("$PY" "$STATE_PY" get --task-dir "$dir" session_id 2>/dev/null || true)"

  "$PY" "$STATE_PY" set --task-dir "$dir" "takeover_at=$(iso_now)" >/dev/null

  # Helper: extract the "Headed Takeover Prompt" section, redacted by default.
  emit_takeover_prompt() {
    local section
    section="$(awk '
      /^## Headed Takeover Prompt/ {flag=1; next}
      /^## / && flag {exit}
      flag {print}
    ' "$dir/handoff.md")"
    if [[ "$raw" -eq 1 ]]; then
      printf '%s\n' "$section"
    else
      printf '%s\n' "$section" | "$PY" "$STATE_PY" redact
    fi
  }

  if [[ "$do_exec" -eq 0 ]]; then
    emit_takeover_prompt
    return 0
  fi

  case "$backend" in
    cursor-agent)
      [[ -n "$sid" && "$sid" != "null" ]] || die "no session id on file"
      exec cursor-agent --resume "$sid"
      ;;
    claude)
      [[ -n "$sid" && "$sid" != "null" ]] || die "no session id on file"
      exec claude --resume "$sid"
      ;;
    codex)
      if [[ -n "$sid" && "$sid" != "null" ]] && command -v codex >/dev/null 2>&1; then
        exec codex resume "$sid"
      fi
      emit_takeover_prompt
      ;;
    *) die "unknown backend: $backend";;
  esac
}

# ---------- entry ------------------------------------------------------------

usage() {
  cat <<'USAGE'
handoff <verb> [args]

Verbs:
  dispatch --backend {cursor|codex|claude} --task "<prompt>" [--slug <slug>] [--model <id>] [--worktree]
  list [--json] [--status <s>] [--safe]
  status <task_id> [--safe]
  cancel <task_id>
  resume <task_id> [--task "<additional>"]
  takeover <task_id> [--exec] [--raw]

State lives in <cwd>/.handoffs/<task_id>/state.json

Redaction:
  takeover output is REDACTED by default (its whole purpose is to paste
  elsewhere). Add --raw to skip redaction when you trust the context.
  list/status accept --safe to opt in to redaction for the same reason.
  Handoff.md on disk stays raw — it's local scratch, not for export.

Pipe redacted output to your clipboard:
  handoff takeover <id> | pbcopy         # macOS
  handoff status <id> --safe | pbcopy
USAGE
}

main() {
  local verb="${1:-}"; shift || true
  case "$verb" in
    dispatch) verb_dispatch "$@" ;;
    list) verb_list "$@" ;;
    status) verb_status "$@" ;;
    cancel) verb_cancel "$@" ;;
    resume) verb_resume "$@" ;;
    takeover) verb_takeover "$@" ;;
    ""|-h|--help|help) usage ;;
    *) die "unknown verb: $verb (see: handoff --help)" ;;
  esac
}

main "$@"
