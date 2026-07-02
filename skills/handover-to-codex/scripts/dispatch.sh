#!/usr/bin/env bash
# Dispatch a task to a headless Codex agent (codex exec) and capture the output.
#
# Usage:   dispatch.sh "<handover prompt>"
# Env vars (all optional):
#   CODEX_MODEL     model id (default: codex config default). Override e.g. gpt-5.3-codex
#   CODEX_SANDBOX   read-only | workspace-write | danger-full-access (default: workspace-write)
#   CODEX_WORKTREE  1 = isolate edits in a git worktree (default), 0 = run in current tree
#   CODEX_OUT       transcript dir/prefix (default: .codex-handovers/<timestamp>)
set -euo pipefail

PROMPT="${1:?usage: dispatch.sh \"<handover prompt>\"}"
MODEL="${CODEX_MODEL:-}"
SANDBOX="${CODEX_SANDBOX:-workspace-write}"
WORKTREE="${CODEX_WORKTREE:-1}"

if ! command -v codex >/dev/null 2>&1; then
  echo "error: codex not found on PATH. Install the Codex CLI." >&2
  exit 127
fi

TS="$(date +%Y%m%d-%H%M%S)"
OUT_BASE="${CODEX_OUT:-.codex-handovers/${TS}}"
mkdir -p "$(dirname "$OUT_BASE")"
EVENTS="${OUT_BASE}.jsonl"
FINAL="${OUT_BASE}.final.md"

WORKDIR="$(pwd)"
WT_PATH=""
if [ "$WORKTREE" = "1" ]; then
  WT_PATH="$(git rev-parse --show-toplevel 2>/dev/null)/.codex-handovers/wt-${TS}"
  git worktree add --detach "$WT_PATH" >&2
  WORKDIR="$WT_PATH"
fi

args=(exec --json -o "$FINAL" -s "$SANDBOX" -C "$WORKDIR" --skip-git-repo-check)
[ -n "$MODEL" ] && args+=(-m "$MODEL")

echo ">> codex ${args[*]}" >&2
echo ">> sandbox: $SANDBOX | worktree: $WORKTREE | model: ${MODEL:-<config default>}" >&2
[ -n "$WT_PATH" ] && echo ">> worktree path: $WT_PATH" >&2
echo ">> events: $EVENTS | final message: $FINAL" >&2

codex "${args[@]}" "$PROMPT" < /dev/null | tee "$EVENTS"

echo "" >&2
echo ">> done. final message: $FINAL" >&2
if [ -n "$WT_PATH" ]; then
  echo ">> review:  git -C $WT_PATH diff" >&2
  echo ">> cleanup: git worktree remove $WT_PATH" >&2
fi
