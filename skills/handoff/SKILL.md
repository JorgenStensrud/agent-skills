---
name: handoff
description: >-
  Dispatch, track, and resume long-running background agent tasks against a
  cursor-agent, codex, or claude backend. Use whenever the user says "hand off
  to cursor / codex / claude", "delegate this to a background agent", "spin up
  a headless agent", "run this detached and check later", "status of the cursor
  handoff", "cancel that handoff", "resume the handoff", or "take over the
  handoff interactively". Every dispatch mints a durable task under
  `.handoffs/<YYYYMMDD-slug>/` with `state.json` (single source of truth) and
  a rendered `handoff.md` cover sheet, so runs survive shell/session crashes
  and are discoverable with `ls`. Six verbs: dispatch, list, status, cancel,
  resume, takeover.
allowed-tools: Bash, Read, Write
---

# handoff

One skill, three backends, six verbs. Delegate a long-running task to a
background CLI agent and get durable, `ls`-discoverable state back — no
in-memory "did it start? I'll poll" ceremony.

Cursor-agent is the opinionated primary. The codex path is intentionally thin:
dispatch, status, cancel only — codex's rescue/resume already lives in the
codex-plugin's `/rescue` command and this skill won't compete with it.

## When this fits

- User says "hand off this to Cursor / Codex / Claude and let me know when it's
  done", "delegate to a background agent", "spin one up detached".
- User asks after the fact: "status of the cursor handoff", "what's cursor
  doing", "list the handoffs", "cancel that one", "resume it", "let me take
  over that chat interactively".
- The task is well-scoped enough that a detached agent won't waste a whole run
  chasing ambiguity. Scope with the user first if it's vague — a headless run
  is a wager on the prompt being good.

## Trust boundary (read once before first dispatch)

- **Cursor** dispatches use `--yolo` (auto-approve every tool call).
- **Claude** dispatches use `--dangerously-skip-permissions` (same idea).
- **Codex** dispatches use `-s workspace-write` (filesystem writes inside cwd,
  no network).

The skill runs on the developer's behalf. Never dispatch into a workspace the
operator has not explicitly named in the invocation. Never accept prompt text
from an untrusted source and hand it straight through — the same rule that
applies to raw `codex exec` and `claude -p` applies here.

## The six verbs

Assume the shim is on `PATH` as `handoff` (or invoke
`~/dev/personal/agent-skills/skills/handoff/scripts/handoff.sh` directly).

### `handoff dispatch --backend {cursor|codex|claude} --task "<prompt>" [--slug <slug>] [--model <id>] [--worktree]`

Starts a headless run. Effects:

1. Validates cwd is absolute and writable.
2. Auto-generates `slug` from the first 5 words of the task if `--slug` isn't
   given. Computes `task_id = YYYYMMDD-<slug>` with `-2`, `-3` suffixes on
   same-day collision.
3. Creates `.handoffs/<task_id>/`, auto-appends `.handoffs/` to `.gitignore`
   the first time it's used in a repo.
4. Mints a session id:
   - **cursor**: `cursor-agent create-chat`. If that fails or prints nothing,
     abort with `refusing to start untracked run`.
   - **claude**: `uuid4` client-side (claude's `--session-id` accepts a
     caller-provided uuid, so we own the handle before launch).
   - **codex**: no id available — stays `null`.
5. Writes `state.json` (status=`running`, attempt 1) and renders `handoff.md`.
6. Launches the backend detached via `nohup`/`setsid`, logs to
   `attempt-1.log`, captures PID + `ps -o lstart=` for the recycled-PID check.
7. Prints `{task_id, backend, session_id, pid, log}` JSON.

Example:

```bash
handoff dispatch --backend cursor \
  --task "Add a /health endpoint to the API server returning {status:'ok'}. Route in server/routes/. Keep tests green."
# -> {"task_id":"20260702-add-a-health-endpoint","backend":"cursor-agent","session_id":"...","pid":54321,"log":".handoffs/20260702-add-a-health-endpoint/attempt-1.log"}
```

### `handoff list [--json] [--status <s>] [--safe]`

Walks `.handoffs/*/state.json` under cwd. For each, reconciles the stored PID:
if state says `running` but `kill -0 <pid>` fails (or `ps lstart` disagrees
with the stored `pid_start`), tails the log for the backend's terminal event
and rewrites status to `done` or `error`. Prints a sorted table by
`updated_at` desc, or JSON with `--json`. `--safe` runs the output through
the redaction filter (see "Redaction" below).

### `handoff status <task_id> [--safe]`

Reconciles as `list` does for one task. Prints the rendered `handoff.md`,
then the last 40 lines of the newest `attempt-N.log`. `--safe` redacts the
output before printing.

### `handoff cancel <task_id>`

Cross-checks the stored `pid_start` against `ps -o lstart= -p <pid>` before
signalling. Refuses to kill if the start time changed (likely a recycled PID).
Then `kill -TERM`, waits up to 5 seconds, `kill -KILL` if still alive.
Sets status=`cancelled`, `exit_code=-15`.

### `handoff resume <task_id> [--task "<additional>"]`

Refuses when status ∈ {running, cancelled}. Bumps to attempt `N+1`.

- **cursor**: `cursor-agent -p --resume <session_id> --output-format stream-json --trust --yolo -- "<prompt>"`
- **claude**: `claude -p --resume <session_id> --output-format stream-json --verbose --dangerously-skip-permissions -- "<prompt>"`
- **codex**: **refused** — points at the codex-plugin `/rescue`. The
  `Headed Takeover Prompt` section of `handoff.md` is the crossover point.

### `handoff takeover <task_id> [--exec] [--raw]`

Without `--exec`: prints the `Headed Takeover Prompt` section of
`handoff.md` so the caller can paste it into an interactive session.
**Output is redacted by default** — its whole purpose is external paste, so
safety is on unless you explicitly opt out with `--raw`.

With `--exec`: execs the backend interactively against the stored session:

- **cursor**: `exec cursor-agent --resume <session_id>` (no `-p`)
- **claude**: `exec claude --resume <session_id>`
- **codex**: `exec codex resume <session_id>` if the CLI supports it in that
  install, else prints the prompt (still redacted unless `--raw`).

`takeover_at` is stamped in `state.json`; status is left untouched (the
interactive shell now owns the chat).

## Redaction — when to apply `--safe` / `--raw`

The skill has a small built-in redaction filter (`state.py redact`) that
scrubs the common leak types before printing: `$HOME`-absolute paths,
`TOKEN=`/`KEY=`/`SECRET=`/`PASSWORD=` env-var assignments, Slack/AWS/GitHub/
OpenAI/Anthropic API tokens, `Bearer <jwt>`, and SSH private-key blocks.

**Trust boundary by design:**

| Data path | Redacted? | Why |
|---|---|---|
| `takeover` output | **Yes, by default** | Meant to paste into another agent, Slack, PR comment, issue — external eyes |
| `takeover --raw` | No | Opt-out when you trust the destination (private notes, personal draft) |
| `list --safe` / `status --safe` | Yes (opt-in) | Same reason — display is being shared |
| `list` / `status` (no flag) | No | Local inspection; user needs the real paths and IDs |
| `dispatch` / `resume` stdout JSON | No | Contains the log path the user must `tail -f` |
| `handoff.md` on disk | No | Local scratch — full context needed for the operator |
| `state.json`, `attempt-*.log` on disk | No | Internal storage; scrub on read, not on write |

**Decision rules for the invoking agent (Claude):**

Reach for `--safe` on `list`/`status`, or trust the takeover default, when
the user's phrasing implies external consumption:

- "share this with the team", "send to Slack", "paste into the PR", "for the
  issue comment", "email the team", "give me something I can copy"
- Explicit clipboard piping: `handoff status <id> --safe | pbcopy`
- Sharing patterns: screenshots for review, public gists, external chat

Skip `--safe` (or use `--raw` on takeover) when:

- User is inspecting their own status locally: "what's it doing", "how far",
  "which one is running", "tail the log"
- User asks for full details / debugging output ("give me the raw log",
  "show everything")
- Context is a private note the user is writing for themselves

When ambiguous, prefer the safer default: `--safe` on list/status if the
result is going anywhere outside the terminal, and don't override the
takeover default unless the user is clearly staying local.

**Never dispatch, resume, or otherwise mutate state based on `--safe`
output** — redaction can drop information the operator needs. `--safe` is
strictly for display / sharing.

## What lives on disk

Per task, one directory under `<cwd>/.handoffs/<task_id>/`:

- `state.json` — single source of truth. Never hand-edit.
- `handoff.md` — human-readable cover sheet. Rendered from state on every
  mutating verb; the skill never hand-edits it either.
- `attempt-1.log`, `attempt-2.log`, ... — append-only stdout+stderr per
  attempt. Never rotated or truncated by the skill.

### `state.json` schema (reference)

```json
{
  "task_id": "YYYYMMDD-slug",
  "backend": "cursor-agent|codex|claude",
  "session_id": "<backend-native uuid or null>",
  "task": "<prompt verbatim>",
  "workspace": "<absolute path>",
  "model": "<id or null>",
  "status": "running|done|error|cancelled",
  "attempts": [
    {
      "n": 1,
      "started_at": "iso",
      "ended_at": "iso|null",
      "pid": 0,
      "pid_start": "<ps lstart string>",
      "exit_code": 0,
      "log": "attempt-1.log"
    }
  ],
  "command": "<argv joined for audit>",
  "created_at": "iso",
  "updated_at": "iso",
  "takeover_at": "iso|null"
}
```

Task id (durable, directory name) is deliberately split from session id
(ephemeral, per-backend chat handle) so retries can mint a fresh chat while
preserving the audit trail. `pid_start` captures `ps -o lstart= -p <pid>` at
spawn so `cancel` can detect a recycled PID and refuse to signal. All
timestamps are ISO-8601 UTC seconds so string-sort equals time-sort.

### `handoff.md` — required cover-sheet fields

The renderer produces these sections and the dispatched agent is expected to
fill in the free-form ones before it stops:

- Status
- Task ID
- Backend
- Session ID
- Workspace
- Model
- Started
- Command
- Logs
- **Latest Summary** — agent-written, one paragraph.
- **What It Tried** — agent-written, brief list.
- **Files Or Areas Touched** — agent-written, paths.
- **Errors Or Blockers** — REQUIRED before stop.
- **Recommended Next Step** — agent-written.
- **Resume Prompt** — pre-filled by the renderer.
- **Headed Takeover Prompt** — REQUIRED before stop.
- **Final Outcome** — filled by whoever closes the task.

**Instruction to the dispatched agent** — the caller should include this
verbatim in the prompt when the task might not finish cleanly:

> Before you stop, write the `Headed Takeover Prompt` and `Errors Or Blockers`
> sections of `.handoffs/<task_id>/handoff.md` verbatim. The Latest Summary
> can lose context on a takeover; these two fields must not.

## Concurrency

State writes are atomic (tmpfile + `os.replace` + `fsync`). The skill assumes
one operator running verbs sequentially against a given `task_id`. Nothing
defends against two `handoff cancel <same-id>` at once beyond the atomic write.

## Worked examples

### Dispatch then check on it

```bash
handoff dispatch --backend cursor --task "Refactor server/routes/scorers.ts to use zod v4."
# -> {"task_id":"20260702-refactor-server-routes-scorers","backend":"cursor-agent",...}

# Later:
handoff list
# task_id                      backend      status     session    updated_at                task
# 20260702-refactor-server-r.  cursor-agent running    a1b2c3d4   2026-07-02T14:22:11+00:00 Refactor server/routes/scorers.ts to use z...

handoff status 20260702-refactor-server-routes-scorers
```

### Cancel a run that's gone off the rails

```bash
handoff cancel 20260702-refactor-server-routes-scorers
```

### Resume a failed run with more context

```bash
handoff resume 20260702-refactor-server-routes-scorers \
  --task "Previous attempt broke the zod imports in server/routes/index.ts — fix those first, then retry the refactor."
```

### Take it over interactively

```bash
# Just show me the prompt I would paste into a fresh cursor chat:
handoff takeover 20260702-refactor-server-routes-scorers

# Or drop straight into the same chat:
handoff takeover 20260702-refactor-server-routes-scorers --exec
```

### List everything that's still running in this repo

```bash
handoff list --status running
```

### Share the takeover prompt with a teammate

```bash
# takeover output is redacted by default — safe to paste into Slack / PR / issue.
handoff takeover 20260702-refactor-server-routes-scorers | pbcopy

# Grab a redacted status snapshot for the standup or a PR comment:
handoff status 20260702-refactor-server-routes-scorers --safe | pbcopy

# You're keeping it local (personal notes, no external eyes) — skip redaction:
handoff takeover 20260702-refactor-server-routes-scorers --raw
```
