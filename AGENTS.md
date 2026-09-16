# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

## Orientering

- Riggen (kontoer, maskiner, sync): [OPPSETT.md](OPPSETT.md)
- Skills som logger inn et sted (legitimasjon, hemmeligheter, publiseringsklar kode): [AUTH.md](AUTH.md)
- Layout- og navnekonvensjoner for skills: [README.md](README.md)

## Den ene regelen

Ingen legitimasjon, ingen personopplysninger og ingen hentede data i repoet. Noen gang.
Repoet er privat i dag, men skal kunne publiseres, og å gjøre et repo offentlig avslører
hele git-historikken. Alt personlig bor i `~/.config/<skill>/` og `~/.local/share/<skill>/`.
Begrunnelsen i sin helhet: [AUTH.md](AUTH.md) §1.

`hooks/pre-commit` kjører `scripts/validate-skills` og `scripts/scan-secrets`. Installer
den én gang per klone: `ln -sf ../../hooks/pre-commit .git/hooks/pre-commit`.

## Sjekker

```bash
scripts/validate-skills                                          # frontmatter, navn, symlinker
scripts/scan-secrets                                             # staged filer
python3 skills/trumf-kvitteringer/tests/test_trumf_kvitteringer.py
```

`validate-skills` melder tre advarsler på Linux (`create-cli`, `github-deep-review`,
`skill-cleaner` er symlinker til `/Users/sten/...`). De er forventet på en ikke-Mac-maskin,
stopper ikke en commit, og har ingenting med endringene dine å gjøre.

## Sjekk om noe faktisk er manuelt

`trumf-kvitteringer` ble først levert som en ren parser fordi bestillingsskjemaet hos Trumf
så ut som noe man måtte klikke seg gjennom. Det gjorde man ikke — skjemaet sender en vanlig
`POST` som et hvilket som helst verktøy kan sende. Se etter kallet i nettverksfanen før du
konkluderer med at et steg må gjøres for hånd.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
