---
name: beam
description: >-
  Use when the user wants to continue a Claude Code session on another machine —
  "beam this to matebook", "continue this on the mac", "teleport/handover
  session across machines", "fetch my session from the other machine". Not for
  handing tasks to background agents (that is the handoff skill).
allowed-tools: Bash, Read
---

# beam

Teleport a Claude Code session between machines. Sessions are plain JSONL files
under `~/.claude/projects/<slug>/`; `beam.sh` rsyncs one session over ssh and
translates the path-slug via `machines.json` (same project lives at different
absolute paths per machine).

## Usage

```bash
skills/beam/beam.sh push <machine> [session-id] [--force]   # send (default: latest for cwd project)
skills/beam/beam.sh pull <machine> [session-id] [--force]   # fetch from remote
skills/beam/beam.sh list <machine>                          # remote sessions for cwd project
```

Run from the project directory. The script prints the exact
`cd … && claude --resume <id>` command to run on the target.

## Rules

1. **Single writer:** close the session on the source machine before resuming
   on the target. Never have the same session open on both.
2. **Diverged target = stop.** If the target copy is larger (resumed there),
   the script refuses; `pull` instead, or `--force` to overwrite knowingly.
3. New machine or moved project → edit `machines.json` (per-project paths +
   `{name}` fallback). Unknown projects fall back to the machine's default root.

## Common mistakes

- Resuming on target while source session still open → forked/corrupt transcript.
- Beaming to a machine where the project dir doesn't exist — the script warns;
  clone the repo there first, then resume.
- Expecting running background jobs to follow — only the transcript moves;
  live jobs stay on the source machine.
