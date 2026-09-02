---
name: unslop
description: >-
  Remove AI slop from code — dead or speculative abstractions, needless layers,
  over-commenting, repetition, defensive guards for impossible cases, names
  that hide meaning. Use when asked to "simplify this", "too much code", "clean
  this up", "remove slop", "this is over-engineered", "make it smaller", or
  after an agent has generated a large diff that needs trimming. Goal: less
  code that does the same thing and reads easier.
---

# unslop

Operasjonell opprydding. Målet er mindre kode som gjør nøyaktig det samme, og
som er lettere å lese. Ikke ny funksjonalitet, ikke «forbedringer» av
oppførsel. Bare fjerning.

## Framgangsmåte

1. Les koden som skal ryddes i sin helhet før du endrer noe.
2. Gå gjennom sjekklisten under, punkt for punkt. Noter hva du fjerner.
3. Kjør tester eller det som finnes av verifikasjon før og etter. Oppførselen
   skal være identisk.
4. Rapporter: linjer før/etter og hva som ble fjernet, kort.

## Sjekkliste: dette leter du etter, og fjerner

**Døde og spekulative abstraksjoner**
- Interfaces, base-klasser og protokoller med én implementasjon. Inline dem.
- Funksjoner som bare kalles ett sted og ikke gir et bedre navn til en blokk.
- Parametre, flagg og options som alltid får samme verdi. Hardkod verdien.
- «Utvidelsespunkter» ingen bruker: registries, hooks, plugin-lister, strategy-
  mønstre for én strategi.
- Generics/typeparametre der én konkret type holder.

**Unødvendige lag**
- Wrapper-funksjoner som bare videresender argumenter til en annen funksjon.
- Service/manager/helper/util-moduler som pakker inn ett bibliotekkall.
- Klasser uten tilstand som kunne vært en funksjon.
- Fabrikker og buildere for objekter som konstrueres ett sted.
- Mellomliggende datastrukturer som bare mappes fra én form til en identisk.

**Overkommentering**
- Kommentarer som gjentar koden (`# increment counter` over `i += 1`). Slett.
- Docstrings som bare omformulerer funksjonsnavnet. Slett.
- Seksjonsbannere, `# ---- Helpers ----`, TODO-er uten eier eller innhold.
- Behold kun kommentarer som forklarer *hvorfor*: et ikke-opplagt valg, en
  workaround for en ekstern feil, en invariant som ikke synes i typene.

**Gjentakelse**
- Samme 3–10 linjer flere steder med små variasjoner. Trekk ut, men bare hvis
  resultatet faktisk er kortere og like tydelig.
- Kopierte try/except- eller error-handling-blokker rundt hvert kall.
- Duplikate konstanter, regexer, meldingsstrenger.

**For defensive guards**
- `if x is None` på ting som aldri kan være None ut fra typene eller
  kallstedene.
- try/except rundt kode som ikke kan feile, eller som fanger `Exception` og
  logger uten å gjøre noe.
- Validering av input som allerede er validert ett lag opp.
- Fallbacks og default-verdier for tilfeller som ikke finnes i programmet.
- `hasattr`/`isinstance`-sjekker der typen er kjent.

**Navn som skjuler mening**
- `data`, `item`, `result`, `obj`, `info`, `tmp`, `value` → navngi etter hva
  det er i domenet (`booking`, `spiller`, `frist`).
- `Manager`, `Handler`, `Processor`, `Helper`, `Util` som suffiks → si hva
  klassen faktisk gjør, eller gjør den om til funksjoner.
- `do_thing_v2`, `new_`, `_impl`, `_internal` → rydd opp i versjoner, behold
  én.
- Boolske parametre som endrer hva funksjonen gjør → to funksjoner.

**Annet støy**
- Ubrukte imports, variabler, funksjoner, filer. Slett, ikke kommenter ut.
- Logging som ikke leses av noen.
- Type-annotasjoner som bare gjentar det åpenbare i dynamiske språk, og
  `Any` som skjuler den ekte typen.
- Konfigurasjon og miljøvariabler for ting som aldri endres.
- README-avsnitt og docs for kode som ikke finnes lenger.

## Regler

- Oppførselen skal være identisk. Finner du en bug underveis, noter den og
  rapporter den separat. Ikke fiks den i samme pass.
- Er du usikker på om noe er dødt: søk etter alle kallsteder først
  (`grep -rn`). Ikke gjett.
- Fjern heller for lite enn for mye, men ikke la «vi kan trenge det» stå. Git
  husker.
- Kortere er ikke automatisk bedre. Én tydelig linje slår tre smarte.
