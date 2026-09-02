---
name: build-simple
description: >-
  Build philosophy for small personal projects (hobby apps, side projects,
  one-person tools). Use when starting, designing, planning, or refactoring a
  feature or a simple project — "how should I build this", "design this
  feature", "start a new app", "refactor this module", "is this
  over-engineered". Eight principles: do the least that works, subtract before
  adding, write for the reader, experience first, build leverage only when
  needed, first principles, model the domain, prove it works.
---

# build-simple

Slik bygger vi enkle prosjekter: hobby-apper, småverktøy, ting én person eier
og vedlikeholder. Ikke teamsystemer, ikke plattformer. Les gjennom prinsippene
før du designer eller refaktorerer noe, og hold deg til dem underveis.

## Prinsippene

1. **Latskaps-protokollen.** Gjør det minste som faktisk løser problemet.
   Ingen config for ting som aldri endres, ingen plugin-system for én plugin,
   ingen «vi trenger nok dette senere». Framtiden du bygger for kommer sjelden,
   og når den kommer ser den annerledes ut.

2. **Trekk fra før du legger til.** Før du skriver ny kode: hva kan fjernes?
   En feature som ingen bruker, et lag som bare videresender, en avhengighet
   som gjør én ting du kunne skrevet på ti linjer. Færre deler betyr færre
   feil og mindre å holde i hodet.

3. **Minimer leser-last.** Skriv for den som leser koden om tre måneder. Det er
   som regel deg selv, uten kontekst. Rett fram slår smart: en tydelig
   `if`-kjede over en elegant reduce, én funksjon som gjør én ting over en
   generisk hjelper med fem flagg.

4. **Opplevelsen først.** Start med hva brukeren skal se og gjøre: skriv
   skjermen, kommandoen eller flyten før du tegner datamodellen. Koden er et
   middel; opplevelsen er målet. Data som ikke støtter en konkret opplevelse
   trenger du ikke.

5. **Bygg vektstangen.** Når du løser noe for tredje gang, bygg grepet som
   løser det for godt: den lille funksjonen eller abstraksjonen som gir
   innflytelse over mange tilfeller. Men først da. En vektstang uten noe å
   løfte er bare en pinne (se punkt 1).

6. **Tenk fra første prinsipper.** Forstå hva problemet faktisk er før du
   velger løsning. Sett opp 2–3 reelle alternativer, si hva hvert enkelt
   koster og gir, og velg bevisst. Ikke lås deg til det første som fungerte
   i en annen kontekst.

7. **Modeller domenet.** Navngi ting etter den ekte verdenen: `spiller`,
   `bytte`, `frist`, `booking`. Ikke `data`, `item`, `manager`, `handler`.
   Når koden leser som en beskrivelse av problemet, forstår du den uten å
   kjøre den.

8. **Bevis at det virker.** Kjør det. Trykk på knappen, kall kommandoen, se på
   outputen. At det kompilerer eller at testen er grønn er ikke det samme som
   at brukeren får det de skulle ha. Gjør det du hevder fungerer, synlig.

## Bruk

- Ved design: skriv opplevelsen (4), vurder alternativer (6), velg det minste
  (1). Navngi etter domenet (7).
- Ved refaktorering: fjern først (2), forenkle for leseren (3), bygg vektstang
  bare der gjentakelsen allerede finnes (5).
- Før du sier «ferdig»: bevis det (8).

Dette er standarden for hvordan vi bygger enkle, utmerkede prosjekter. Mindre
kode, tydeligere navn, bevist oppførsel.
