---
name: handover-to-codex
description: >-
  Hand a coding task off to a Codex agent (codex CLI, `codex exec`) running
  headless, the same way you'd dispatch a subagent — but the work executes in
  Codex and lands in this repo. Use whenever the user wants to delegate, hand
  off, or "create a Codex agent" for a task: phrases like "hand this to Codex",
  "spin up a codex agent", "let Codex do X", "delegate this to codex", "have
  Codex implement/fix/refactor Y", or "create a codex handover". Also use when
  the user wants OpenAI's model (GPT-5 / Codex) to take a task while Claude
  stays the orchestrator. Builds a self-contained handover prompt with repo
  context, runs `codex exec`, and reports the result back. For the Cursor
  equivalent, see the handover-to-cursor skill.
---

# Handover to Codex

Delegate a task to a **Codex agent** running headless in this repo, then bring
the result back. Think of it as dispatching a subagent — except the worker is
`codex exec`, running OpenAI's model with its own context, tools, and sandbox.

## When this fits

- User wants Codex (not Claude) to do the actual edits.
- User wants a second model / second opinion while Claude orchestrates.
- A task is well-scoped enough to hand off and check later.

If the task is vague, **scope it with the user first** — a Codex agent runs
detached, so a fuzzy prompt wastes a whole run. Nail down: what to change, which
files, how to verify.

## Prerequisites (check once, fast)

```bash
command -v codex          # must resolve; else tell user to install the Codex CLI
codex exec --help >/dev/null 2>&1 && echo ok
```

Auth: Codex needs `codex login` (interactive) or an OpenAI API key in its config
/ `OPENAI_API_KEY`. If a run fails on auth, ask the user to run `! codex login`.

## The flow

1. **Build the handover prompt.** The agent only knows what you tell it plus what
   it reads. Make it self-contained:
   - **Goal**: one sentence, the outcome.
   - **Context**: current branch, what's already done/in-flight, why this task.
   - **Files / entry points**: name the real paths so it doesn't hunt blind.
   - **Constraints**: conventions to follow, what NOT to touch, tests to keep green.
   - **Done means**: the concrete acceptance check (build passes, test X green,
     endpoint returns Y).
   Pull this from the conversation and a quick repo look (`git status`,
   `git log --oneline -5`, the relevant files) — don't make the user repeat it.

2. **Pick sandbox + isolation + model.** State your choices to the user before
   running so the handoff isn't a surprise.
   - **Sandbox** (`CODEX_SANDBOX`): `workspace-write` (default — edits the repo,
     no network), `read-only` (propose only, no edits — good for "what would you
     do" or risky changes), `danger-full-access` (only if the user explicitly
     wants network/outside-repo access).
   - **Isolation** (`CODEX_WORKTREE=1`, default): runs in a fresh `git worktree`
     so edits don't collide with the user's working tree. Set `0` to edit in place.
   - **Model** (`CODEX_MODEL`): omit to use the user's Codex config default;
     override with e.g. `gpt-5.3-codex`.

3. **Run it** via the helper, which captures the JSONL event stream and the
   final message:

   ```bash
   .claude/skills/handover-to-codex/scripts/dispatch.sh "<handover prompt>"
   ```

   Env knobs (all optional): `CODEX_MODEL`, `CODEX_SANDBOX`, `CODEX_WORKTREE=0`,
   `CODEX_OUT=path` (transcript dir/file).

   The script runs `codex exec --json -o <final-message-file> -s <sandbox>`, so
   it executes non-interactively. Run it in the **background** for big tasks
   (`run_in_background: true`) and poll, so the user isn't blocked.

4. **Report back.** When it finishes, read the saved final message + transcript,
   summarize what the agent did, point at the worktree path (or changed files),
   and state whether the "done means" check passed. If it ran in a worktree:

   ```bash
   git -C <worktree-path> diff            # review
   git -C <worktree-path> log --oneline   # what it committed, if anything
   # then merge / cherry-pick, or open the worktree in the editor
   ```

   The script prints the worktree path when it makes one. Clean up with
   `git worktree remove <path>` once the work is pulled in.

## Resuming / iterating

A handover is one detached run. To continue the same Codex session:

```bash
codex exec resume --last "<follow-up>"      # most recent session
codex exec resume <session-id> "<follow-up>"
```

## Code review handoff

Codex has a dedicated review mode — hand it a diff to critique without editing:

```bash
codex exec review        # review current repo changes
```

## Safety notes

- `workspace-write` lets the agent write files and run shell commands inside the
  workspace without prompting — that's the point of headless. **Scope matters**:
  don't hand off destructive or repo-wide rewrites without the user's nod.
- `danger-full-access` removes the sandbox (network + filesystem). Only use it
  when the user explicitly asks and understands why.
- Default worktree isolation keeps the user's tree clean — only drop it
  (`CODEX_WORKTREE=0`) when the user wants in-place edits.
- Codex reads `AGENTS.md` (and project `.rules`) if present, so repo conventions
  carry over automatically.

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
