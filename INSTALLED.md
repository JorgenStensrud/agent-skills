# Global tooling — what's active in every Claude Code session

Snapshot of my user-scope plugins, MCP servers, and personal skills. All of these
load automatically when Claude Code starts, in any project. Project-scope plugins
(only active in one repo) are not listed here.

## User-scope plugins

Live under `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`. Config in
`~/.claude/plugins/installed_plugins.json`. Marketplace refresh cache in
`~/.claude/plugins/marketplaces/`.

| Plugin | Marketplace | Purpose |
|---|---|---|
| `superpowers` | claude-plugins-official | Brainstorming, systematic-debugging, TDD, verification-before-completion, subagent-driven-development, receiving/requesting code-review, executing/writing plans, git-worktrees, dispatching-parallel-agents, superpowers-index |
| `caveman` | caveman (JuliusBrussee) | Ultra-compressed communication mode (this) |
| `codex` | openai-codex | Codex CLI integration — rescue, setup, gpt-5-4-prompting, cli-runtime, result-handling |
| `frontend-design` | claude-plugins-official | Distinctive, production-grade UI generation |
| `skill-creator` | claude-plugins-official | Create/improve/measure skills |
| `pyright-lsp` | claude-plugins-official | Python language server for type checking |
| `tmux-sidebar` | local | tmux integration |

## User-scope MCP servers

Load per session, defined in `~/.claude/claude_desktop_config.json` or via
`/mcp` interactive config.

| MCP | Source | Purpose |
|---|---|---|
| `harvest` | user config | Time-logging (log_time, list_projects, timers, expenses) |
| `context7` | user config | Live library docs (fetch React/Django/etc current docs) |
| `linear` | user config | Linear tickets (issues, projects, comments, statuses) |

## claude.ai-hosted MCP servers

Bound to your claude.ai login, follow the session — not locally installed.

| MCP | Purpose |
|---|---|
| Forte Pulse | Forte Digital internal Pulse data (DAX, parquet, TFSO surfaces) |
| MCP Drop | Publish quick shareable pages |
| MCP10X | Flowcase CVs, PowerPoint generation, agentic skills |
| Notion | Notion workspace |
| Google Calendar | (needs auth — see /plugin) |

## Personal skills

Live in this repo. `~/.claude/skills` is a symlink to `./skills`.

| Skill | Purpose | Source |
|---|---|---|
| `handoff` | Unified cross-backend background dispatch — verbs: dispatch, list, status, cancel, resume, takeover. Backends: cursor-agent (primary), codex, claude. State repo-locally in `.handoffs/<YYYYMMDD-slug>/`. | Own — built here |
| `clipboard` | Write a clipboard-ready prompt/message for pasting elsewhere (Slack, PR description, another agent). Renamed from Peter Steinberger's `handoff` skill so the name doesn't collide with our own. | Copied from [openclaw/agent-skills](https://github.com/openclaw/agent-skills)/skills/handoff — single markdown file, no scripts. Manual update if upstream changes. |
| `skill-cleaner` | Skill audit: budget, usage, duplicates, compact descriptions. Keeps the growing skill collection from turning into porridge. | Symlink → `~/dev/personal/steipete-agent-scripts/skills/skill-cleaner`. Auto-updates via `git -C ~/dev/personal/steipete-agent-scripts pull`. |
| `create-cli` | CLI UX/spec conventions: args, flags, help, output, errors, config, dry-run. | Symlink → same clone. Auto-updates via git pull. |
| `github-deep-review` | Deep GitHub PR review — fetch remote PR, read changed code first, distinguish stale-vs-real, propose the best fix. Fills the "review a GitHub PR in any repo" gap that codex plugin's `/review` doesn't cover (it targets local git state). | Symlink → same clone. Auto-updates via git pull. |

- Add: `mkdir skills/<name>` + `SKILL.md` with YAML frontmatter (`name`, `description`)
- Remove: `git rm -r skills/<name>`
- Rename: `git mv skills/<old> skills/<new>` and update the `name:` field

## Pointer skills (one skill, points to a real toolset elsewhere)

Single-skill wrappers whose only job is to be discoverable globally and route
you into the real skills that live in another repo. Prefer this over
symlinking many external skills — one entry in Available skills, not six.

| Skill | Points to | Purpose |
|---|---|---|
| `defending-code` | `~/dev/work/defending-code-reference-harness` | Anthropic vuln-discovery harness. Lists the 6 real sub-skills (quickstart, threat-model, vuln-scan, triage, patch, customize) and how to reach them (cd into the repo, they're active there). |

Upstream sources should carry the actual skills — the wrapper just tells you
where. To update: `git pull` in the source repo.

## Auto-update behavior

**Plugins:** Marketplace refreshes periodically (last check timestamp in
`~/.claude/plugins/known_marketplaces.json`). New plugin versions are pulled
when the marketplace cache updates. `/plugin update <name>` forces a refresh.
Manual re-install: `/plugin install <name>`.

**MCP servers:** Static config unless you edit it. `context7`, `harvest`,
`linear` don't self-update — they connect to remote servers that evolve
independently.

**Symlinked external skills:** Do NOT auto-update. They point to a git clone,
so `git pull` in the source repo is required. Add a monthly reminder if the
upstream is active.

**Personal skills in this repo:** Only change when you edit and commit here.
No auto-updates by design — that's the whole point of owning the repo.

## Precedence

If a skill name exists in multiple places, project-local wins over user-scope,
which wins over global. Order:

1. `<repo>/.claude/skills/<name>/` — project-tracked skill
2. `<repo>/.claude/skills/<name>/` — project-local, gitignored via `.git/info/exclude`
3. `~/.claude/skills/<name>/` — personal (this repo, via symlink)
4. `~/.claude/plugins/cache/*/skills/<name>/` — plugin-provided

## Health checks

```bash
# What's installed?
jq '.plugins | keys' ~/.claude/plugins/installed_plugins.json
# Marketplace freshness
jq '.[] | {name: (input_filename), lastUpdated}' ~/.claude/plugins/known_marketplaces.json
# Personal skill count
ls ~/.claude/skills/ | wc -l
# Broken symlinks?
find ~/.claude/skills/ -maxdepth 2 -type l ! -exec test -e {} \; -print
```
