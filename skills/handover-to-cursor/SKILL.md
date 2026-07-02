---
name: handover-to-cursor
description: >-
  Hand a coding task off to a Cursor agent (cursor-agent CLI) running headless,
  the same way you'd dispatch a subagent — but the work executes in Cursor and
  lands in this repo. Use whenever the user wants to delegate, hand off, or
  "create a Cursor agent" for a task: phrases like "hand this to Cursor", "spin
  up a cursor agent", "let Cursor do X", "delegate this to cursor-agent", "have
  Cursor implement/fix/refactor Y", or "create a cursor handover". Also use when
  the user wants a second model (GPT-5, Codex) to take a task while Claude stays
  the orchestrator. Builds a self-contained handover prompt with repo context,
  runs cursor-agent, and reports the result back.
---

# Handover to Cursor

Delegate a task to a **Cursor agent** running headless in this repo, then bring
the result back. Think of it as dispatching a subagent — except the worker is
`cursor-agent`, so it can run a different model (GPT-5, Codex) and uses Cursor's
own context, rules, and tools.

## When this fits

- User wants Cursor (not Claude) to do the actual edits.
- User wants a second opinion / second model on a task while Claude orchestrates.
- A task is well-scoped and self-contained enough to hand off and check later.

If the task is vague, **scope it with the user first** — a Cursor agent runs
detached, so a fuzzy prompt wastes a whole run. Nail down: what to change, which
files, how to verify.

## Prerequisites (check once, fast)

```bash
command -v cursor-agent          # must resolve; else tell user to install Cursor CLI
cursor-agent --list-models       # also confirms auth; if it errors → run: cursor-agent login
```

If not authenticated, `cursor-agent login` is interactive — ask the user to run
`! cursor-agent login` themselves, or to set `CURSOR_API_KEY`.

## The flow

1. **Build the handover prompt.** This is the whole game — the agent only knows
   what you tell it plus what it reads. Make it self-contained:
   - **Goal**: one sentence, the outcome.
   - **Context**: current branch, what's already done/in-flight, why this task.
   - **Files / entry points**: name the real paths so it doesn't hunt blind.
   - **Constraints**: conventions to follow, what NOT to touch, tests to keep green.
   - **Done means**: the concrete acceptance check (build passes, test X green,
     endpoint returns Y).
   Pull this from the conversation and a quick repo look (`git status`,
   `git log --oneline -5`, the relevant files) — don't make the user repeat it.

2. **Pick isolation + model.** Default to a **worktree** (`-w`) so the agent's
   edits don't collide with the user's working tree. Use the user's current
   branch as base. Model: `auto` unless the user wants a specific one
   (`cursor-agent --list-models` for the list; e.g. `gpt-5.3-codex`, `sonnet-4`).

3. **Run it** via the helper, which streams progress and captures the transcript:

   ```bash
   .claude/skills/handover-to-cursor/scripts/dispatch.sh "<handover prompt>"
   ```

   Flags via env vars (all optional):
   - `CURSOR_MODEL=gpt-5.3-codex` — pick the model.
   - `CURSOR_WORKTREE=0` — disable worktree, edit current tree in place.
   - `CURSOR_PLAN=1` — plan/read-only mode (agent proposes, doesn't edit). Good
     for "what would you do" handoffs or risky changes.
   - `CURSOR_OUT=path.md` — where to save the transcript (default under
     `.cursor-handovers/`).

   The script runs `cursor-agent -p --force --trust --output-format stream-json`
   so it executes non-interactively with full tool access. Run it in the
   **background** if it's a big task (`run_in_background: true`) and poll, so the
   user isn't blocked.

4. **Report back.** When it finishes, read the saved transcript, summarize what
   the agent did, point at the worktree path (or changed files), and state
   whether the "done means" check passed. If it ran in a worktree, tell the user
   how to bring it in:

   ```bash
   git -C <worktree-path> diff            # review
   # merge / cherry-pick / or just open the worktree in the editor
   ```

## Resuming / iterating

A handover is one detached run. To continue the same Cursor thread (follow-up
instructions, fixes):

```bash
cursor-agent ls                          # find the chat id
cursor-agent --resume <chatId> -p --force --trust "<follow-up>"
```

## Safety notes

- `--force`/`--yolo` + `--trust` let the agent run shell commands and write files
  without prompting. That's the point of headless, but it means **scope matters**.
  Don't hand off destructive or repo-wide-rewrite tasks without the user's nod.
- Default worktree isolation keeps the user's tree clean — only drop it
  (`CURSOR_WORKTREE=0`) when the user explicitly wants in-place edits.
- The agent obeys `.cursor/rules`, `AGENTS.md`, and `CLAUDE.md` if present, so
  repo conventions carry over automatically.

## Example handover prompt

```
Goal: Add a /health endpoint to the API server returning {status:"ok"}.

Context: Branch main. Express server in server/, started via npm run dev.
Routes live in server/routes/. No health check exists yet.

Files: server/index.ts (app setup), server/routes/index.ts (route registration).

Constraints: Follow existing route style (see server/routes/scorers.ts). Don't
touch the frontend. Keep existing tests green.

Done means: `curl localhost:3000/health` returns 200 {status:"ok"}, and
`npm test` still passes.
```
