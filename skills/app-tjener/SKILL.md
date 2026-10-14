---
name: app-tjener
description: >-
  Serversiden av en liten app (Node): integrasjoner mot eksterne tjenester og programmer
  (Google Sheets, bank, smarthus, CLI-er) med tre moduser — av, falsk og ekte — så
  testene aldri går på nett. Falske tjenester og falske programmer i test, status som
  sier hva som mangler, oppsett som merkes uten omstart, koble-skript som sender
  hemmeligheter over ssh, og feilkoder som blir setninger brukeren kan handle på.
---

# Serversiden av en liten app

Erfaring fra en app med én Node-server og mange integrasjoner (regneark, bank,
kalender, smarthus, en kode-CLI som underprosess), der hver av dem kunne testes uten
konto og uten nett.

## Slå opp etter oppgave

| Oppgave | Les |
| --- | --- |
| Ny integrasjon, testmodus, «aldri ekte nett i tester», en tjeneste som ikke er satt opp ennå, koble til med en nøkkel | [reference/falske-tjenester.md](reference/falske-tjenester.md) |
| En LLM-agent i appen: verktøy, politikk, fremmed tekst, faux-modellen | skillen `agent-i-appen` |
| Deploy, systemd, versjon, HTTPS, SSRF-sperren for henting | skillen `pwa` (reference/drift.md) |

## Reglene

1. **Hver integrasjon har tre moduser — av, falsk og ekte — bak ett grensesnitt**, valgt
   ett sted fra miljøet. Resten av appen vet ikke hvilken den har.
2. **`status()` sier hva som mangler**, i en setning med veien videre. Mangler oppsettet,
   er tjenesten av, ikke krasjet.
3. **Testene går aldri på nett.** Hver integrasjon har en falsk som testene setter opp;
   det som ikke er under test, er av.
4. **Forfalsk så langt ut som mulig**, så den ekte koden kjører: en falsk tjeneste bak
   grensesnittet, et falskt program på stien, ikke en mock av funksjonen som kaller det.

Grensen mot `agent-i-appen`: den forfalsker modellen, denne forfalsker tjenestene.
