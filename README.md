# agent-skills

Personal skill library for Claude Code (and optionally Codex).

> **Hvordan hele riggen henger sammen (kontoer, maskiner, sync, beam): se [OPPSETT.md](OPPSETT.md).**

- Layout: each skill lives in `skills/<name>/SKILL.md` with YAML frontmatter (`name`, `description`).
- Discovery: `~/.claude/skills` is a symlink to `./skills` — every Claude Code session reads from here automatically.
- Scope: personal only. Not tied to any single project. For team-shared skills, use the repo's own `.claude/skills/`.
- Optional Codex sync: `ln -s ~/dev/personal/agent-skills/skills ~/.codex/skills` to share the same set across both CLIs.

## Adding a skill

1. `mkdir skills/<name>` and create `SKILL.md` with:
   ```yaml
   ---
   name: <name>
   description: "Short trigger phrase — used for routing, keep generic."
   ---
   ```
2. Body: terse and operational. Helper scripts under `skills/<name>/scripts/` when needed.
3. Commit. Next Claude Code session picks it up.

## Removing / renaming a skill

- Rename: `git mv skills/<old> skills/<new>` and update the `name:` field.
- Remove: `git rm -r skills/<name>`.

## Precedence with project-local skills

If a project's `<repo>/.claude/skills/<name>/` shares a name with one here, the project-local one wins for that session. Fine for per-project overrides.

## Skill conventions (enforced by `scripts/validate-skills`)

Skills are the main routing layer — the description string is what determines whether the agent picks the skill for a given prompt. Rules:

- **Frontmatter must be well-formed YAML** — starts on line 1, closes with `---`.
- **`name:` present, non-empty, unique across all skills**. Match the folder name unless the rename is intentional (e.g. `clipboard/` renamed from Peter's `handoff` to avoid collision with our own `handoff`).
- **`description:` present, ≤500 chars**. Short, generic, trigger-optimized — not documentation. Detailed docs belong in the SKILL.md body.
- **Quote the `description:`** (either `"..."` on one line or `>-` for a folded block). Unquoted long strings trip up YAML tools.
- **Keep skill bodies terse and operational.** Helper scripts under `skills/<name>/scripts/` when a workflow has repeatable commands.
- **Symlinked skills must resolve** — a broken symlink is a hard error.
- **No stray `__pycache__/`** inside skill folders (already gitignored, but warn if present).

Run the validator manually anytime:

```bash
scripts/validate-skills           # errors + warnings, exit 1 on errors
scripts/validate-skills --strict  # warnings also fail
```

## Install the pre-commit hook

From the repo root, one-time:

```bash
ln -sf ../../hooks/pre-commit .git/hooks/pre-commit
```

Now every `git commit` runs `scripts/validate-skills` first. To bypass in a pinch: `git commit --no-verify` (rare).
