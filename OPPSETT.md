# Sånn funker skills & Claude-riggen hos meg

Én kilde til sannhet: **dette repoet**. Alt annet er symlinker inn hit.

Unntaket er skills som har fått eget repo — i dag `oda-kvitteringer` og `trumf-kvitteringer`
i [`digital-kjoleskap`](https://github.com/JorgenStensrud/digital-kjoleskap). De symlinkes
inn i `skills/` herfra og oppfører seg ellers likt; se README-en der for kommandoen.

```
                    agent-skills (dette repoet)
                    ├── skills/          ← alle skills
                    ├── config/          ← settings.json + statusline
                    └── skills/beam/     ← øktteleport mellom maskiner

   MAC                                    MATEBOOK
   ~/dev/personal/agent-skills            ~/dev/personal/agent-skills
        ▲ symlinker                            ▲ symlinker
   ┌────┴─────────┬──────────────┐        ┌────┴─────────┬──────────────┐
   ~/.claude      ~/.claude-seeyou        ~/.claude      ~/.claude-seeyou
   (forte)        (seeyou)                (forte)        (seeyou)
```

## Kontoer og aliaser (samme på begge maskiner)

| Alias | Konto | Config-dir |
|---|---|---|
| `claude` / `cc-forte` / `claude-forte` | forte (fortedigital) | `~/.claude` |
| `cc-seeyou` / `claude-seeyou` | seeyou (jorgen@seeyou.eu) | `~/.claude-seeyou` |
| `claude-dang` | forte, skip permissions | `~/.claude` |

To kontoer = to separate rate limits. Login er det **eneste** som ikke deles.

## Hva deles med hvem

| | Mellom kontoer (samme maskin) | Mellom maskiner |
|---|---|---|
| Skills | ✅ symlink → repo | ✅ via git/rsync av repoet |
| Settings (modell, permissions, plugins) | ✅ symlink → repo | ✅ samme |
| Plugins (installasjoner) | ✅ symlink → `~/.claude/plugins` | ❌ per maskin (auto-installeres) |
| Økter + memory (`projects/`) | ✅ symlink → `~/.claude/projects` | ❌ — bruk **beam** |
| Login + MCP-tilkoblinger | ❌ per konto | ❌ per konto per maskin |

Konsekvens: endrer du en skill eller settings ett sted → gjelder alle kontoer
på den maskinen umiddelbart, og den andre maskinen etter sync.

## Ny skill

```bash
mkdir skills/<navn>          # + SKILL.md med name/description-frontmatter
git commit                   # pre-commit-hook validerer
```
Ferdig — begge kontoer har den med én gang, matebook etter sync. Detaljer: README.md.

## Sync mellom maskiner

Repoet bor privat på GitHub under `JorgenStensrud`. gh har to kontoer, so push krever bytte:

```bash
gh auth switch -u JorgenStensrud && git push && gh auth switch -u jorgenseeyou
```

Matebook har ikke GitHub-auth (ennå) — sync dit fra Macen:

```bash
rsync -a --exclude .DS_Store ~/dev/personal/agent-skills/ matebook:'~/dev/personal/agent-skills/'
```

## Flytte en økt (handover)

**Samme maskin, mellom kontoer:** ingenting å gjøre. Lukk økta, åpne med den
andre kontoen, `/resume`, velg økta. Delt `projects/` = begge ser alt.

**Mellom maskiner:** bruk beam (eller bare si «beam denne til matebook» i en økt):

```bash
cd <prosjektmappa>
skills/beam/beam.sh push matebook    # eller: pull matebook / list matebook
# → printer cd … && claude --resume <id> å kjøre på målmaskinen
```

Sti-forskjeller (mac `~/dev/personal/X` vs matebook `~/X`) håndteres av
`skills/beam/machines.json` — nytt prosjekt med avvikende sti → legg det inn der.

Konto spiller ingen rolle: økter er bare filer og kjører på kontoen som
resumer dem. forte@matebook → seeyou@mac funker.

## Regler (de eneste som betyr noe)

1. **Én skriver per økt.** Aldri samme økt åpen fra to kontoer eller to maskiner samtidig. Lukk før du resumer et annet sted.
2. **`projects/` skal aldri inn i git** — transkripter er private, repoet kan bli delt.
3. **Ny maskin?** Clone repoet, symlink `settings.json`/`skills`/`plugins`/`projects` som i diagrammet, legg inn aliaser, `/login` per konto. (Fasit: se hvordan matebook er rigget.)
