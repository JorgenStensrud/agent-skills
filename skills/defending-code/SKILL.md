---
name: defending-code
description: >-
  Entry point for the Anthropic defending-code-reference-harness — an
  autonomous vulnerability discovery and remediation pipeline for Claude.
  Use when asked to "threat model a repo", "scan for vulns", "triage
  security findings", "patch these bugs", "port the vuln pipeline to <X>",
  or generally when the user wants a recon → find → verify → report → patch
  loop against a target codebase. The 6 real skills (quickstart, threat-model,
  vuln-scan, triage, patch, customize) live in the harness repo itself, not
  here — this wrapper tells you how to reach them and when each fits.
---

# Defending Code — pointer skill

The actual work happens in the Anthropic
[defending-code-reference-harness](https://github.com/anthropics/defending-code-reference-harness),
cloned locally at:

```
~/dev/work/defending-code-reference-harness/
```

That repo carries 6 real skills in `.claude/skills/`. They activate automatically
when you open Claude Code **inside that repo**. This skill exists so the pointer
is discoverable from any project — spot the trigger, then `cd` there.

## The 6 sub-skills (in the harness repo)

| Skill | Slash cmd | When |
|---|---|---|
| `quickstart` | `/quickstart` | Orient in the harness. Blank arg = 30-sec intro. With a question = answered from the repo's own docs + source. First thing to try. |
| `threat-model` | `/threat-model` | Build THREAT_MODEL.md for a target codebase. Modes: `interview` (owner-driven), `bootstrap` (from code + CVEs), or chained. |
| `vuln-scan` | `/vuln-scan` | Static source-code vuln scan. Reads target dir + THREAT_MODEL.md, fans out parallel review subagents per focus area, writes VULN-FINDINGS.{json,md}. Read-only. |
| `triage` | `/triage` | Triage a batch of raw findings — verify real, dedupe, re-rank by exploitability, tag owners. Writes TRIAGE.{json,md}. |
| `patch` | `/patch` | Generate + verify patches for confirmed findings. Consumes TRIAGE.json, writes PATCHES/. |
| `customize` | `/customize` | Port the pipeline to a new language / vuln class / detection mechanism (default is C/C++ memory via Docker + ASAN). |

## Pipeline shape

```
/threat-model  →  /vuln-scan  →  /triage  →  /patch
    (context)      (find)         (filter)     (fix)
```

`/quickstart` orients. `/customize` retargets the pipeline.

## How to reach it

```bash
cd ~/dev/work/defending-code-reference-harness
# Then in Claude Code, invoke /quickstart or one of the other slash cmds.
# The skills are already active in that repo — no install needed.
```

If the clone is missing:

```bash
gh repo clone anthropics/defending-code-reference-harness ~/dev/work/defending-code-reference-harness
```

## When NOT to use

- Not for reviewing a small diff — that's `/code-review` or `security-reviewer` agent.
- Not for enforcing style/lint — that's `applying-*-conventions` skills.
- Not for CVE lookups against dependencies — that's `security-guidance` plugin territory.

## Upstream status

Not maintained, no contributions accepted. Anthropic offers Claude Security as
the managed alternative. Local clone updates: `git -C ~/dev/work/defending-code-reference-harness pull`.
