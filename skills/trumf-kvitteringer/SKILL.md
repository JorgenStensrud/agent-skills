---
name: trumf-kvitteringer
description: >-
  Brukerens egne Trumf-kvitteringer via bin/trumf-kvitteringer: bestill innsynsdumpen,
  sjekk om den er klar, hent den, og les den. Bruk når brukeren spør om kjøp hos KIWI,
  MENY, Spar eller Joker, matutgifter over tid, hva han har handlet, eller vil importere
  en Trumf-innsynsfil. Kun brukerens egne data.
---

# trumf-kvitteringer

All logikk ligger i `bin/trumf-kvitteringer`. Denne filen sier bare når og hvordan.

Dekker NorgesGruppen: KIWI, MENY, Spar, Joker.

## Når dette passer

- «Hva har jeg brukt på mat hos KIWI i år?»
- «Hvor mye melk kjøper jeg?»
- «Bestill Trumf-dataene mine» / «er dumpen klar?»
- «Importer Trumf-dumpen min»

## Veien, i fire steg

```bash
bin/trumf-kvitteringer oppsett      # én gang per maskin
bin/trumf-kvitteringer bestill      # SISTE_3_AR, JSON
bin/trumf-kvitteringer bestilling   # er den klar?
bin/trumf-kvitteringer hent         # last ned + importer
```

Deretter, uten nettverk:

```bash
bin/trumf-kvitteringer status
bin/trumf-kvitteringer kvitteringer --fra 2026-01-01 --kjede KIWI
bin/trumf-kvitteringer varer --limit 20
```

JSON på stdout, diagnostikk på stderr.
**Exit:** 0 = ok, 1 = delvis, 2 = feil med forklaring, 3 = gjorde ingenting med vilje.

## Bestillingen tar tid. Ikke vent på den.

Trumf har **inntil 30 dager** på seg, selv om det ofte går mye raskere. Verktøyet venter
aldri aktivt, og du skal heller ikke gjøre det: legg inn bestillingen, si fra til brukeren
at den er lagt inn, og avslutt. Neste gang han spør, kjør `bestilling`.

**Ikke løkk på `bestilling` eller `hent`.** Ett kall, så rapporter.

## Dobbeltbestilling

`bestill` nekter av seg selv når det allerede finnes en bestilling — også når statuskallet
mot Trumf feiler, da stoler den på sitt eget notat. Da får du exit 3 og
`"status": "allerede_bestilt"`.

**Ikke send `--paa-nytt` for å komme forbi det.** Det erstatter bestillingen brukeren
allerede venter på, og starter ventetiden på nytt. Spør ham først.

## Har brukeren ingen sesjon

`oppsett` må kjøres én gang per maskin. Innloggingen hos Trumf har SMS-tofaktor, så den
skjer i nettleseren — verktøyet tar imot informasjonskapslene etterpå og fornyer tokenet
selv derfra.

> Kjør `bin/trumf-kvitteringer oppsett` i terminalen. Den forklarer hvor i
> utviklerverktøyene du finner det som skal limes inn.

**Ikke be om passord eller SMS-kode i chatten.** Et passord skrevet her havner i
transkriptet, og et skript som ber om engangskoden din er umulig å skille fra svindel.

Sier verktøyet at sesjonen er utløpt, er svaret det samme: kjør `oppsett` igjen. Aldri
tolk det som at brukeren ikke har handlet.

## Har brukeren allerede en dump

Da trengs ingen innlogging i det hele tatt:

```bash
bin/trumf-kvitteringer inspiser <fil>   # gjør dette først på en ny fil
bin/trumf-kvitteringer importer <fil>
```

`inspiser` viser strukturen med **bare feltnavn, typer og antall** — ingen butikknavn,
ingen beløp, ingen datoer. Den rapporten er trygg å dele hvis parseren må oppdateres.
`kvitteringer` og `varer` er det ikke.

## Hvis importen ikke finner kvitteringer

Da er formatet et annet enn parseren kjenner. Verktøyet sier det, og returnerer aldri en
tom liste som om brukeren ikke hadde handlet. Kjør `inspiser <fil>` og oppdater
feltlistene øverst i skriptet — ett listeelement per nytt navn.

## Personopplysninger

Kvitteringene er brukerens egne kjøp — hvor han handler, når, og hva han spiser.

- Ikke lim kvitteringsdata, medlemsnummer eller informasjonskapsler inn i repoet.
- Sesjonen ligger i `~/.config/trumf-kvitteringer/`, dataene i
  `~/.local/share/trumf-kvitteringer/`. Utenfor repoet med vilje. La dem ligge der.

## Tester

```bash
python3 skills/trumf-kvitteringer/tests/test_trumf_kvitteringer.py
```

Faste svar, ingen nettverk, ingen ekte kvitteringer.
