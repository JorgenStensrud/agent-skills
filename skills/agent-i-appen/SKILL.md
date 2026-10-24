---
name: agent-i-appen
description: >-
  En LLM-agent inne i en app (Pi eller annen tool use / function calling): skriveverktøy
  som legger til, retter, haker av eller sletter delte data via appens eget API,
  systemprompt, politikk håndhevet i kode, sesjon og kontekst på serveren, agent som
  leser nettsider, e-post eller annen fremmed tekst (prompt injection, eksfiltrering,
  SSRF), og testing uten API-nøkkel. Tidligere agent-skriveverktoy.
---

# En agent inne i en app

Erfaring fra to små apper med én server, delte data og en agent i en fane, begge med
en Pi-agent (pi-coding-agent) på serveren.
Mønstrene gjelder ethvert verktøybrukende LLM-oppsett; kodeeksemplene er Pi.

## Slå opp etter oppgave

| Oppgave | Les |
| --- | --- |
| Agenten skal kunne endre data: verktøyenes form, svaret som manus, systemprompten, politikken som utvidelse, testing med faux-modellen, ferdigheter og politikk i fire nivåer, forslag og ja, styring av fysiske ting | [reference/skriveverktoy.md](reference/skriveverktoy.md) |
| Sesjonen på serveren, lagring, innlogging, kontekst-trimming, fersk tilstand før hver tur, modellvalg, PDF-lesing, kommandoer | [reference/sesjon-og-kontekst.md](reference/sesjon-og-kontekst.md) |
| Agenten leser tekst utenfra (nettsider, søk, e-post, banktekster, kalenderinvitasjoner) og kan også sende noe ut eller styre noe | [reference/fremmed-tekst.md](reference/fremmed-tekst.md) |
| Chat og strømming i nettleseren, push fra agenten | skillen `pwa` |
| Falske versjoner av tjenestene agenten bruker, i test | skillen `app-tjener` |

## Reglene som kostet mest å lære

1. **Skriv gjennom appens eget HTTP-API, med `node:http`.** Validering, ett sted som
   skriver, og agenten ser det brukerne ser. Ikke `fetch` når agenten kjører i
   serverprosessen: Pi bytter dispatcheren, og kall til localhost tok sekunder.
2. **Verktøyresultatet er manus for svaret.** Lever en ferdig `sammendrag`-setning med
   de identifiserende feltene, og den gamle verdien ved endring.
3. **Det agenten *kan*, håndheves i kode før kallet**, ikke i prompten: hvitliste av
   verktøy, sletting bare på brukerens egne ord i de to siste meldingene, journal over
   gjennomførte endringer.
4. **Fremmed tekst er data, aldri beskjeder.** Etter at agenten har lest noe utenfra, går
   ingenting ut resten av turen, og en ny melding alene åpner ikke igjen: det som går
   ut, må brukeren selv ha bedt om. En adresse hentes, og en lenke i svaret er
   klikkbar, bare når brukeren selv skrev den; bilder i svaret bare fra eget opphav.
   To enkle regler holdt der tre runder med smarte hvitlister ikke gjorde det.
5. **Test hele loopen uten legitimasjon**, gjennom samme samtalemodul som drift, mot
   en ekte server i en tom datamappe. Kall aldri den ekte modellen i en test.
