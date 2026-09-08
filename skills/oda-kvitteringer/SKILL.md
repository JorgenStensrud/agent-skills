---
name: oda-kvitteringer
description: >-
  Hent brukerens egne ordrer og kvitteringer fra oda.com via bin/oda-kvitteringer.
  Bruk når brukeren spør om sine Oda-kjøp, matutgifter, hva han har handlet, hvor mye
  noe har kostet over tid, eller vil eksportere ordrehistorikken sin. Krever pålogging
  én gang per maskin. Kun brukerens egne data.
---

# oda-kvitteringer

All logikk ligger i `bin/oda-kvitteringer`. Denne filen sier bare når og hvordan.

## Når dette passer

- «Hva brukte jeg på mat i august?»
- «Hvor ofte kjøper jeg avokado?»
- «Eksporter Oda-ordrene mine»
- «Hva kostet den siste handelen?»

Ikke for: å legge varer i kurv, søke i sortimentet eller bestille. Dette leser
ordrehistorikk, ingenting annet.

## Kommandoer

```bash
bin/oda-kvitteringer status              # er sesjonen i live?
bin/oda-kvitteringer ordrer --limit 10   # nyeste ordrer
bin/oda-kvitteringer ordre 12345678      # én ordre, normalisert
bin/oda-kvitteringer hent                # alle ordrer til disk, inkrementelt
bin/oda-kvitteringer raa 12345678        # uendret API-svar
```

JSON på stdout, diagnostikk på stderr. Exit 0 = ok, 2 = feil med forklaring.

Analyse gjøres på de hentede filene i `~/.local/share/oda-kvitteringer/ordrer/`,
ikke ved å kalle API-et på nytt. Kjør `hent` én gang, jobb på disk etterpå.

## Hvis sesjonen mangler eller er utløpt

Verktøyet sier fra selv, med kommandoen som fikser det:

```
Sesjonen mot Oda er utløpt eller mangler.
Kjør:  oda-kvitteringer oppsett
```

**Be brukeren kjøre `bin/oda-kvitteringer oppsett` i terminalen sin, og stopp der.**

Ikke spør om passordet i chatten. Det havner i økttranskriptet, og transkripter
skal aldri inn i git (se `OPPSETT.md`). Oppsett kjøres én gang per maskin —
legitimasjon synkes ikke mellom maskiner, og det er med vilje.

## Hvis noe annet feiler

Verktøyet skiller mellom «ingen data» og «noe er galt», og sier aldri det første
når det egentlig er det andre. Les feilmeldingen — den sier hva som skjedde:

- **Formendring** («mangler items.item_groups») — Oda har endret API-et. Kjør
  `raa <ordrenummer>` og se hva som faktisk kommer. Ikke rapporter det som at
  brukeren ikke har handlet.
- **`_meta.advarsel_priser`** — ordredetaljene inneholdt ingen prisfelter. Enten
  har ikke Oda dem der, eller så heter de noe annet enn ventet. `raa` viser det,
  og feltnavnet legges så til i `LINE_TOTAL_KEYS` i skriptet.
- **HTTP 425/429** — Oda er under press. Verktøyet venter og prøver igjen selv.
  Ikke kjør det i en løkke ved siden av.

## Personopplysninger

Ordredataene er brukerens egne kjøp — hvor han handler, når, og hva han spiser.

- Ikke lim ordredata inn i repoet, i en commit, eller i en fil under prosjektet.
- `raa` skriver ekte data til stdout. Vis utdrag, ikke hele dumper, med mindre
  brukeren ber om det.
- Hentede filer ligger utenfor repoet med vilje. La dem ligge der.
