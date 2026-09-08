---
name: trumf-kvitteringer
description: >-
  Les brukerens egne Trumf-kvitteringer fra innsynsdumpen via bin/trumf-kvitteringer.
  Bruk når brukeren spør om kjøp hos KIWI, MENY, Spar eller Joker, matutgifter over tid,
  hva han har handlet, eller vil importere en Trumf-innsynsfil. Parser, ikke skraper —
  ingen innlogging. Kun brukerens egne data.
---

# trumf-kvitteringer

All logikk ligger i `bin/trumf-kvitteringer`. Denne filen sier bare når og hvordan.

Dekker NorgesGruppen: KIWI, MENY, Spar, Joker.

## Når dette passer

- «Hva har jeg brukt på mat hos KIWI i år?»
- «Hvor mye melk kjøper jeg?»
- «Importer Trumf-dumpen min»

## Viktig: dette er en parser, ikke en skraper

Verktøyet logger **ikke** inn noe sted og gjør **ingen** nettverkskall. Brukeren
bestiller sine egne data hos Trumf, og verktøyet leser filen.

Det er et bevisst valg, ikke en begrensning: trumf.no viser 12 måneder, mens Trumf
lagrer kvitteringer i **tre år**. Innsynsdumpen gir altså mer data enn skraping ville
gitt, og krever ingen automatisert innlogging.

**Ikke foreslå å automatisere bestillingen.** Den er manuell med vilje.

## Har brukeren ingen dump ennå

Be ham bestille den, og stopp der:

> https://www.trumf.no/trumf-profil/innsyn-og-utlevering → be om utlevering
> (dataportabilitet). Legg filen et sted, og si fra når den er der.

Det tar tid å få den. Ikke vent aktivt.

## Kommandoer

```bash
bin/trumf-kvitteringer inspiser <fil>      # hva ER dette? struktur uten verdier
bin/trumf-kvitteringer importer <fil>      # parse og lagre
bin/trumf-kvitteringer status              # hva ligger på disk
bin/trumf-kvitteringer kvitteringer --fra 2026-01-01 --kjede KIWI
bin/trumf-kvitteringer varer --limit 20    # summer per vare, dyreste først
```

JSON på stdout, diagnostikk på stderr. Exit 0 = ok, 2 = feil med forklaring.

**Kjør `inspiser` først på en ny dump.** Formatet er ikke verifisert mot ekte data
(se README), og `inspiser` viser om parseren kjenner igjen feltene — uten å vise
en eneste verdi.

## Hvis importen ikke finner kvitteringer

Da er formatet et annet enn parseren kjenner. Verktøyet sier det, og returnerer
aldri en tom liste som om brukeren ikke hadde handlet.

Kjør `inspiser <fil>`. Utdataene inneholder **bare feltnavn, typer og antall** —
ingen butikknavn, ingen beløp, ingen datoer. Den rapporten er trygg å dele, og er
det som skal til for å oppdatere feltlistene øverst i skriptet.

## Personopplysninger

Kvitteringene er brukerens egne kjøp — hvor han handler, når, og hva han spiser.

- Ikke lim kvitteringsdata inn i repoet eller i en commit.
- `inspiser` er trygg å dele. `kvitteringer` og `varer` er det ikke.
- Importerte filer ligger utenfor repoet med vilje. La dem ligge der.
