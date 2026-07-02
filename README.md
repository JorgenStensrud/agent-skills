# agent-skills

Personal skill library for Claude Code (and optionally Codex).

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
