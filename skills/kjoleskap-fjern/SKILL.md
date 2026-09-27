---
name: kjoleskap-fjern
description: >-
  Brukerens mat- og handledata (Oda- og Trumf-kvitteringer, SQLite-indeksen, Oda-
  handlelister og -handlekurv) fra maskinen som eier dem, over ssh — for maskiner som ikke har
  digital-kjoleskap klonet. Bruk ved «hva har jeg kjøpt», «hva bruker vi på mat»,
  «hva kjøper vi hver uke», «legg til i handlelista», når kjoleskap-skillen ikke finnes
  lokalt. Ingen data eller innlogging på denne maskinen.
---

# kjoleskap-fjern

Dataene og innloggingene bor på én maskin som alltid står på (standard `matebook`),
i repoet `digital-kjoleskap`. Den henter fra Oda og Trumf hver morgen og bygger
SQLite-indeksen. Denne skillen sender kommandoen dit over ssh og gir deg JSON-svaret
uendret — samme kommandoer som `kjoleskap`, `oda-kvitteringer` og `trumf-kvitteringer`.

Har maskinen `kjoleskap`-skillen selv (digital-kjoleskap klonet), bruk den i stedet;
med `kjoleskap fjern` påslått gjør den det samme.

## Kommandoer

```bash
skills/kjoleskap-fjern/bin/kjoleskap-fjern status                  # indeksen, siste synk, handlinger
skills/kjoleskap-fjern/bin/kjoleskap-fjern skjema                  # tabellene — les før du skriver SQL
skills/kjoleskap-fjern/bin/kjoleskap-fjern varer --limit 20 --sok melk
skills/kjoleskap-fjern/bin/kjoleskap-fjern forbruk --gruppering maaned
skills/kjoleskap-fjern/bin/kjoleskap-fjern sql "SELECT …"          # skrivebeskyttet

skills/kjoleskap-fjern/bin/kjoleskap-fjern oda lister              # Oda-handlelister
skills/kjoleskap-fjern/bin/kjoleskap-fjern oda sok "kjøttdeig"
skills/kjoleskap-fjern/bin/kjoleskap-fjern oda legg-til <liste> <produkt[:antall]>...
skills/kjoleskap-fjern/bin/kjoleskap-fjern oda kurv                # handlekurven
skills/kjoleskap-fjern/bin/kjoleskap-fjern oda kurv fra-liste <liste>

skills/kjoleskap-fjern/bin/kjoleskap-fjern trumf status
```

Annen vert eller sti: `KJOLESKAP_VERT=<ssh-vert> KJOLESKAP_STI=<sti>`. Kjøres skillen på
selve verten (maskinnavnet er det samme som `KJOLESKAP_VERT`), går kommandoen lokalt
uten ssh — så den virker likt overalt.

## Regler

1. **Exit 255 er ssh, ikke dataene.** Verten er av, eller denne maskinen når den ikke
   (Tailscale av?). Si det til brukeren; ikke tolk det som «ingen kjøp».
2. **Les fritt, skriv bare på forespørsel.** Spørringer er trygge. `oda legg-til`,
   `oda fjern` og `oda kurv legg-til/fjern/fra-liste` endrer lista eller kurven på
   oda.com: følg reglene i `oda-kvitteringer` (vis produktene og antall først, én
   `legg-til` med alt). Bestilling og betaling gjør brukeren i appen.
3. **Ikke kjør `synk`, `trumf hent`, `trumf bestill` eller `trumf hent-direkte`**
   uten at brukeren ber om det — det går på nett mot Oda og Trumf, og den faste
   synken gjør det hver morgen uansett.
4. **Innlogging skjer på verten, aldri her.** Sier `status` at en sesjon er utløpt, er
   det brukeren som logger inn i en nettleser; sesjonen kan pipes inn med
   `kjoleskap-fjern trumf oppsett --json-stdin < fil`. Ingen passord eller SMS-kode i
   chatten.
5. **Ingenting lagres her.** Svarene er brukerens egne kjøp — vis sammendrag, skriv
   dem ikke til filer, repoer eller memory.
