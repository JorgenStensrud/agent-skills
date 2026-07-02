#!/usr/bin/env bash
# Dispatch a task to a headless Cursor agent and capture the transcript.
#
# Usage:   dispatch.sh "<handover prompt>"
# Env vars (all optional):
#   CURSOR_MODEL     model id (default: auto). See: cursor-agent --list-models
#   CURSOR_WORKTREE  1 = isolate edits in a git worktree (default), 0 = edit in place
#   CURSOR_PLAN      1 = plan/read-only mode (propose, don't edit), default 0
#   CURSOR_OUT       transcript path (default: .cursor-handovers/<timestamp>.jsonl)
set -euo pipefail

PROMPT="${1:?usage: dispatch.sh \"<handover prompt>\"}"
MODEL="${CURSOR_MODEL:-auto}"
WORKTREE="${CURSOR_WORKTREE:-1}"
PLAN="${CURSOR_PLAN:-0}"

if ! command -v cursor-agent >/dev/null 2>&1; then
  echo "error: cursor-agent not found on PATH. Install the Cursor CLI." >&2
  exit 127
fi

TS="$(date +%Y%m%d-%H%M%S)"
OUT="${CURSOR_OUT:-.cursor-handovers/${TS}.jsonl}"
mkdir -p "$(dirname "$OUT")"

args=(-p --force --trust --output-format stream-json --model "$MODEL")
[ "$WORKTREE" = "1" ] && args+=(--worktree "handover-${TS}")
[ "$PLAN" = "1" ] && args+=(--plan)

echo ">> cursor-agent ${args[*]}" >&2
echo ">> transcript: $OUT" >&2
echo ">> model: $MODEL | worktree: $WORKTREE | plan: $PLAN" >&2

# Stream to stdout (so caller sees progress) AND save raw events to the transcript.
cursor-agent "${args[@]}" "$PROMPT" | tee "$OUT"

echo "" >&2
echo ">> done. transcript saved to $OUT" >&2
