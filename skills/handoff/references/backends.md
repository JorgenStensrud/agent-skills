# Backend flag tables

Concrete commands the `handoff` skill uses per backend. Kept short and
code-block-heavy so both humans and the skill can copy verbatim.

## cursor-agent (primary)

Cursor is the opinionated primary because the codex-plugin already covers
codex's rescue/resume UX well and there is no equivalent for cursor.

```bash
# 1. Mint a chat handle up-front (this is the forum-post rule: if we can't
#    capture the id, we refuse to launch — an untracked run is worse than no run).
session_id="$(cursor-agent create-chat)"

# 2. Dispatch headless against that id.
cursor-agent -p --resume "$session_id" \
  --output-format stream-json \
  --trust --yolo \
  [--model <id>] \
  -- "<prompt>"

# 3. Resume headless (new attempt against same chat).
cursor-agent -p --resume "$session_id" \
  --output-format stream-json --trust --yolo \
  [--model <id>] \
  -- "<follow-up-prompt>"

# 4. Interactive takeover — reopens the exact chat.
cursor-agent --resume "$session_id"
```

Terminal event to reconcile against in the log:

```json
{"type":"result","subtype":"success","is_error":false,"duration_ms":...,"usage":{...}}
```

Quirks:

- `--yolo` auto-approves every tool call with no confirmation prompt. That is
  the point of headless — but it makes SKILL.md's trust boundary load-bearing.
- `--trust` only takes effect together with `-p`; interactive mode ignores it.
- `create-chat` must succeed. If it prints nothing or exits non-zero, abort
  with `"refusing to start untracked run"`. Never launch a headless cursor run
  whose chat id we did not capture.

## codex (secondary, thin)

Codex path is intentionally minimal: dispatch, status, cancel. Resume is
explicitly refused and points to the codex-plugin `/rescue` command.

```bash
# Dispatch.
codex exec --json --skip-git-repo-check -s workspace-write \
  [--model <id>] \
  -- "<prompt>"

# No `--resume` here on purpose — see the codex-plugin.
```

Terminal event to reconcile against:

```json
{"type":"turn.completed", ...}
```

(Also accept `task.completed` / `result` for forward-compat with newer codex
builds.)

Quirks:

- `--skip-git-repo-check` is required when the workspace is a `git worktree`
  because codex otherwise complains that HEAD is detached under `.git/worktrees/`.
- `workspace-write` is the sandbox: filesystem writes inside `cwd`, no network.
  If a task truly needs network, the operator should run codex directly with
  `-s danger-full-access` — the skill will not offer that flag.

## claude (secondary, thin)

Claude Code CLI supports a caller-provided `--session-id`, so we mint a uuid4
client-side and own the handle before launch — same principle as cursor's
`create-chat`, just cheaper.

```bash
session_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"

# Dispatch.
claude -p --output-format stream-json --verbose \
  --dangerously-skip-permissions \
  --session-id "$session_id" \
  [--model <id>] \
  -- "<prompt>"

# Resume headless.
claude -p --output-format stream-json --verbose \
  --dangerously-skip-permissions \
  --resume "$session_id" \
  [--model <id>] \
  -- "<follow-up-prompt>"

# Interactive takeover.
claude --resume "$session_id"
```

Terminal event to reconcile against:

```json
{"type":"result","subtype":"success","is_error":false,"duration_ms":...,"usage":{...}}
```

Quirks:

- `--dangerously-skip-permissions` auto-approves tool calls with no prompt.
  Same trust boundary as `--yolo` on cursor — the caller is on the hook for
  scoping the workspace.
- `--session-id` accepts any uuid; we mint uuid4 so the id is unambiguously
  ours and the launch is atomic (no create-then-look-up race).
- `--verbose` is required together with `-p --output-format stream-json`
  for the stream events to actually be emitted.
