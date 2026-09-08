# trumf-kvitteringer

Les dine egne Trumf-kvitteringer — KIWI, MENY, Spar, Joker — fra innsynsdumpen.
Ett kjørbart skript, ingen avhengigheter utover Python 3.9+ stdlib.

**Dette er en parser, ikke en skraper.** Ingen innlogging, ingen nettverkskall,
ingen legitimasjon å lagre.

## Hvorfor innsyn og ikke skraping

Ikke av forsiktighet — fordi det gir mer data for mindre arbeid:

| | trumf.no | Innsyn |
|---|---|---|
| Hvor langt tilbake | 12 måneder | inntil 3 år |
| Butikknavn | kjede-ID | klartekst |
| Automatisert innlogging | nødvendig | ingen |

Trumfs egen personvernerklæring sier at «kvitteringer lagres i tre år», mens
kvitteringssiden sier «siste 12 måneder». Nettsidene viser altså mindre enn Trumf
faktisk har. Innsyn henter resten.

## Skaff dumpen

1. Logg inn på <https://www.trumf.no/trumf-profil/innsyn-og-utlevering>
2. Be om **utlevering (dataportabilitet)** — **ikke** innsyn
3. Velg lengst mulig periode. Trumf lagrer kvitteringer i tre år.
4. Vent. Du får beskjed når filen er klar.

### Steg 2 er ikke en detalj

MENY, som er samme konsern, sier det rett ut om innsyn:

> «Innsynet vil gi deg tilgang til dine personopplysninger i **PDF-format**.»

PDF kan ikke parses maskinelt. **Utlevering** er noe annet: personvernforordningen
artikkel 20 krever et «strukturert, vanlig brukt og maskinlesbart format», altså
JSON eller CSV. Det er det formatet dette verktøyet leser — og det olejorgenb fikk
i 2019.

Verktøyet oppdager feilen for deg: peker du det på en PDF, eller på en zip som bare
inneholder PDF, sier det hva som gikk galt og hva du skal be om i stedet.

Trumf bekrefter at du får dine egne kjøp: *«Digitale kvitteringer er kun synlig for
den som faktisk har kjøpt varen. Dersom du ber om innsyn eller dataportabilitet, får
du kun opplysninger om dine egne kjøp.»*

### Kan bestillingen automatiseres?

Kort svar: **bestillingen kanskje, leveringen nei — og leveringen er det som avgjør.**

- Bestillingen er **selvbetjent i nettleseren**, ikke en e-post til et personvernombud.
  Trumf: *«Som innlogget på trumf.no kan du bestille innsyn og styre dine
  innstillinger.»* MENY: *«Der vil du enkelt og raskt kunne bestille innsyn innenfor
  ulike områder av persondata, og selv definere hvilken periode du ønsker.»*
  Siden er en vanlig rute i Trumfs egen webapp (`/trumf-profil/innsyn-og-utlevering`).
- **Om det ligger ett API-kall bak knappen, vet jeg ikke.** Logikken finnes ikke i
  noen kodepakke som kan hentes uten å være logget inn — rutenavnet er alt som ligger
  åpent. Å svare på det krever én innlogget observasjon, og den må du gjøre selv.
- **Leveringen er asynkron.** Trumf: *«Vi besvarer henvendelsen din så fort som mulig,
  og senest innen 30 dager.»* Det er ingen nedlastingslenke som dukker opp med det
  samme.

Derfor: selv om bestillingen lot seg automatisere fullt ut, kan innsyn ikke være en
jevnlig synkronisering. Det er en **engangs-etterfylling** av dyp historikk. Vil du ha
noe som kjører ofte, er plattform-API-et veien — se avsnittet om EAN-strekkoder — men
det gir bare 12 måneder og krever at du kopierer sesjonen fra nettleseren.

Vil du finne ut hva som ligger bak knappen: åpne nettverksfanen før du trykker
«bestill», og se om det kommer et kall mot `platform-rest-prod.ngdata.no` eller
`api.ngdata.no`. Det er nok til å avgjøre om et `bestill`-steg kan bygges.

## Bruk

```bash
bin/trumf-kvitteringer inspiser ~/Nedlastinger/trumf-innsyn.json   # gjør dette først
bin/trumf-kvitteringer importer ~/Nedlastinger/trumf-innsyn.json
bin/trumf-kvitteringer status
bin/trumf-kvitteringer kvitteringer --fra 2026-01-01 --kjede KIWI
bin/trumf-kvitteringer varer --limit 20
```

JSON på stdout, så det piper til `jq`:

```bash
bin/trumf-kvitteringer varer | jq -r '.[] | "\(.sum_belop)\t\(.varenavn)"' | head
```

Import er idempotent — samme dump to ganger gir ikke duplikater. Kjører du en ny
dump senere, slås den sammen med det du allerede har.

Leser `.json`, JSON-linjer og `.zip` med JSON i.

## Hvor ting ligger

`~/.local/share/trumf-kvitteringer/kvitteringer/` — én JSON-fil per kvittering,
`0600`. Utenfor repoet, fordi dette repoet skal kunne gjøres offentlig og det
avslører hele git-historikken. Se [`AUTH.md`](../../AUTH.md).

Overstyr med `TRUMF_KVITTERINGER_DATA_DIR`.

## Hva du får ut

```json
{
  "kvitteringsnummer": "K-1",
  "dato": "2026-08-14",
  "kjede": "KIWI",
  "butikknavn": "KIWI Testveien",
  "totalbelop": 63.10,
  "bonus": null,
  "varelinjer": [
    {"varenavn": "TINE Lettmelk 1L", "antall": 2.0, "belop": 41.60, "ean": null}
  ],
  "_meta": {
    "antall_varelinjer": 1,
    "sum_varelinjer": 41.60,
    "ukjente_varelinjefelter": []
  }
}
```

Summen av varelinjene avstemmes mot totalen. Spriker de, sier `_meta.advarsel_sum`
fra — det fanger opp at parsingen mistet noe, eller at det er rabatt eller pant på
kvitteringen.

## Uverifisert: feltnavnene

**Dette er det viktigste forbeholdet.** Parseren er bygget mot feltnavn fra
[`olejorgenb/trumf_receipt_tools`](https://github.com/olejorgenb/trumf_receipt_tools)
(2019) og [`ttyridal/trumf-data-fetch`](https://github.com/ttyridal/trumf-data-fetch),
ikke mot en dump vi har sett. Antakelsen er at et GDPR-eksportformat er stabilt over
tid, siden det ikke er en produktflate — men det er en antakelse.

Derfor:

- Hvert felt gjenkjennes under **flere navn**, både innsyn-varianten (`varenavn`,
  `vareBelop`, `vareAntallVekt`) og plattform-API-varianten (`vareTekst`, `belop`,
  `antall`, `ean`).
- Både norsk desimalkomma og punktum håndteres.
- Ukjente felter **rapporteres** i `_meta` i stedet for å forsvinne.
- Et ukjent format **feiler høylytt**. Det returnerer aldri en tom liste som om du
  ikke hadde handlet.

`inspiser` finnes nettopp for dette. Den viser strukturen med **bare feltnavn, typer
og antall — ingen verdier**:

```json
{
  "kvitteringer_funnet": 2,
  "struktur_uten_verdier": {
    "dato": "<dato-lignende tekst>",
    "butikknavn": "<tekst, 14 tegn>",
    "varelinjer": [{"varenavn": "<tekst, 16 tegn>"}, "... 2 elementer"]
  },
  "gjenkjente_felter": {"dato": "dato", "butikknavn": "butikknavn"}
}
```

Den rapporten kan deles for å få parseren oppdatert uten at et eneste butikknavn
eller beløp forlater maskinen din. Nye feltnavn legges inn i listene øverst i
skriptet — ett listeelement per navn.

## Hvis du heller vil ha EAN-strekkoder

Innsynsdumpen ser ikke ut til å ha EAN. Plattform-API-et
(`platform-rest-prod.ngdata.no/trumf/husstand/transaksjoner`) har det, men gir bare
12 måneder og krever at du kopierer `Authorization`-headeren fra en innlogget
nettleser hver gang sesjonen dør.

Parseren leser begge formater, så henter du en slik dump selv, kan den importeres
med samme kommando. Det er bare ikke noe dette verktøyet gjør for deg.

## Vilkår

Trumfs medlemsvilkår sier ingenting om automatisert tilgang. Sanksjonene der gjelder
bonusmisbruk — «misbruk av fordeler eller forsøk på urettmessig tilegnelse av bonus».
Å lese sine egne kvitteringer er ikke det.

Denne veien er uansett den ryddigste som finnes: innsyn og dataportabilitet er
rettigheter Trumf selv tilrettelegger for på profilsiden.
