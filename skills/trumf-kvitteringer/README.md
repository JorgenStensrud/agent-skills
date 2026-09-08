# trumf-kvitteringer

Dine egne Trumf-kvitteringer — KIWI, MENY, Spar, Joker — hele veien: bestill
innsynsdumpen, vent, hent den, les den.

Ett kjørbart skript, ingen avhengigheter utover Python 3.9+ stdlib.

```bash
bin/trumf-kvitteringer oppsett      # én gang per maskin
bin/trumf-kvitteringer bestill      # siste 3 år, JSON
bin/trumf-kvitteringer bestilling   # er den klar?
bin/trumf-kvitteringer hent         # last ned + importer
```

Har du allerede en dump, hopper du rett til `importer <fil>` — da trengs ingen
innlogging i det hele tatt.

## Hvorfor innsyn og ikke skraping

Ikke av forsiktighet — fordi det gir mer data:

| | trumf.no | Innsyn |
|---|---|---|
| Hvor langt tilbake | 12 måneder | inntil 3 år |
| Butikknavn | kjede-ID | klartekst |
| Varelinjer | per kvittering, 12 mnd | per kvittering, 3 år |

Trumfs egen personvernerklæring sier at kvitteringer lagres i tre år, mens
kvitteringssiden viser «siste 12 måneder». Nettsidene viser altså mindre enn Trumf
faktisk har.

Trumf bekrefter selv hva du får: *«Digitale kvitteringer er kun synlig for den som
faktisk har kjøpt varen. Dersom du ber om innsyn eller dataportabilitet, får du kun
opplysninger om dine egne kjøp.»*

### Bestillingen er ikke manuell

Første versjon av dette verktøyet var en ren parser, fordi bestillingsskjemaet på
profilsiden så ut som noe man måtte klikke seg gjennom. Det stemte ikke. Skjemaet
sender en helt vanlig `POST`, og den kan et hvilket som helst verktøy sende:

```
POST https://platform-rest-prod.ngdata.no/innsyn
Authorization: Bearer <token>
FWC-Chain-Id: 133
Content-Type: application/json

{"medlemId": "...", "onskerProfil": false, "onskerDigitalHistorikk": false,
 "onskerDialoghistorikk": false, "onskerOrdrehistorikk": false,
 "onskerSalgshistorikk": true, "onskerSalgshistorikkPerHandel": true,
 "periode": "SISTE_3_AR", "format": "JSON"}

→ 201 Created
```

`FWC-Chain-Id: 133` er NorgesGruppens kjede-id, og den må være med — uten den stopper
brannmuren kallet før det når API-et.

**Feltene betyr:**

| Felt | Gir deg |
|---|---|
| `onskerSalgshistorikkPerHandel` | kjøpstransaksjoner per handel per vare — **varelinjene** |
| `onskerSalgshistorikk` | bonustransaksjoner |
| `format: "JSON"` | maskinlesbar utlevering. `"INNSYN"` gir PDF, som er langt verre å parse |

Begge de to første står på som standard. Vil du bare ha det ene:
`--uten-varelinjer` eller `--uten-bonus`. Merk at uten varelinjer har parseren
ingenting å gjøre.

**Periode:** `SISTE_3_AR` er standard. Gyldige verdier er `SISTE_3_MANEDER`,
`SISTE_6_MANEDER`, `SISTE_12_MANEDER`, `SISTE_2_AR`, `SISTE_3_AR`.

### Ventetiden forsvinner ikke

Trumf har **inntil 30 dager** på seg til å levere. Ofte går det mye raskere, men
verktøyet er bygget for at det kan ta lang tid:

- `bestill` skriver et notat om at du har bestilt, i `~/.config/trumf-kvitteringer/`.
- `bestilling` spør Trumf om status og forteller hvor lenge du har ventet.
- Ingenting venter aktivt, poller i løkke eller kjører i bakgrunnen.

## Pålogging

Innloggingen hos Trumf går over telefonnummer, passord og SMS-kode. **Verktøyet ser
aldri passordet ditt, og skal aldri be om engangskoden.** Du logger inn i nettleseren
som vanlig, og `oppsett` tar imot sesjonen etterpå:

1. Logg inn på <https://www.trumf.no>
2. F12 → Nettverk → høyreklikk en forespørsel til `www.trumf.no` → **Kopier som cURL**
3. `bin/trumf-kvitteringer oppsett` og lim inn hele kommandoen

Verktøyet plukker ut informasjonskapslene og kaster resten. Du kan også lime inn bare
`Cookie:`-headeren.

Finner du **`idsrv`** blant kapslene (Applikasjon → Cookies → `id.trumf.no`), ta den
med. Den er langlevd, og med den kan verktøyet skaffe seg en ny sesjon gjennom
OAuth-omdirigeringene når www-sesjonen dør — i praksis forskjellen på å lime inn igjen
hver uke og å slippe.

`oppsett` verifiserer med et ekte kall før den sier at det gikk bra, og henter
medlemsnummeret ditt fra tokenet (`http://id.trumf.no/claims/medlem`). Uten det kan
ingen bestilling legges inn, og da sier den fra.

### Når tokenet går ut

Tilgangstokenet lever kort. Hvert kall sjekker `exp` og fornyer ved behov, i tre steg:

1. `GET /api/auth/getToken` med sesjonskapslene
2. `GET /api/auth/session` → `accessToken`
3. `GET /api/login?providerHandle=trumf-personal` med `idsrv`, følg omdirigeringene,
   og prøv 1 på nytt med den ferske sesjonen

Nye kapsler fra hvert svar tas vare på underveis — også fra hvert hopp i
omdirigeringskjeden, som er grunnen til at verktøyet følger omdirigeringene selv i
stedet for å la `urllib` gjøre det.

Slår alle tre feil, sier verktøyet **at du må logge inn på nytt**. Det returnerer aldri
en tom liste som om du ikke hadde handlet.

## Dobbeltbestilling

`bestill` nekter når det allerede finnes en bestilling. Den spør Trumf først
(`OrderActive` eller `OrderReady`), og faller tilbake på sitt eget notat hvis
statuskallet feiler — å bestille i blinde er verre enn å ikke bestille.

```json
{
  "status": "allerede_bestilt",
  "kilde": "Trumf",
  "klar": false,
  "bestilt": "2026-03-16T22:54:28",
  "ventet_dager": 4.2,
  "neste_steg": "Er den klar, kjør 'trumf-kvitteringer hent'. ..."
}
```

Exit 3, ikke 0 og ikke 2: verktøyet gjorde ingenting, med vilje. `--paa-nytt`
overstyrer, men erstatter da bestillingen du allerede venter på.

## Bruk

```bash
bin/trumf-kvitteringer status                       # hva ligger på disk
bin/trumf-kvitteringer kvitteringer --fra 2026-01-01 --kjede KIWI
bin/trumf-kvitteringer varer --limit 20
bin/trumf-kvitteringer inspiser <fil>               # struktur uten verdier
bin/trumf-kvitteringer importer <fil>               # uten innlogging
bin/trumf-kvitteringer logout                       # glem sesjonen
```

JSON på stdout, så det piper til `jq`:

```bash
bin/trumf-kvitteringer varer | jq -r '.[] | "\(.sum_belop)\t\(.varenavn)"' | head
```

Import er idempotent — samme dump to ganger gir ikke duplikater. En ny dump senere
slås sammen med det du har.

Leser `.json`, JSON-linjer og `.zip` med JSON i.

## Hvor ting ligger

```
~/.config/trumf-kvitteringer/
  session.json       informasjonskapsler, token, medlemsnummer   0600
  bestilling.json    notat om at du har bestilt                  0600
~/.local/share/trumf-kvitteringer/
  dumper/            nedlastede zip-filer                        0600
  kvitteringer/      én JSON-fil per kvittering                  0600
```

Utenfor repoet, fordi dette repoet skal kunne gjøres offentlig og det avslører hele
git-historikken. Se [`AUTH.md`](../../AUTH.md).

Overstyr med `TRUMF_KVITTERINGER_CONFIG_DIR` og `TRUMF_KVITTERINGER_DATA_DIR`.

## Hva du får ut

```json
{
  "kvitteringsnummer": "10001",
  "dato": "2026-03-12",
  "kjede": null,
  "butikknavn": "KIWI 999 Testveien",
  "totalbelop": 63.10,
  "bonus": null,
  "varelinjer": [
    {"varenavn": "TESTMELK 1L", "antall": 2.0, "belop": 41.60, "ean": null}
  ],
  "_meta": {"antall_varelinjer": 1, "sum_varelinjer": 41.60}
}
```

Summen av varelinjene avstemmes mot totalen. Spriker de, sier `_meta.advarsel_sum`
fra — det fanger opp at parsingen mistet noe, eller at det er rabatt eller pant på
kvitteringen.

## Hva som ikke er verifisert mot levende tjeneste

**Ingenting her er kjørt mot en ekte Trumf-konto.** Verktøyet er bygget mot et
fungerende oppsett som gjorde nøyaktig det samme (bestilling, statussjekk, nedlasting,
fornying), og testet mot faste svar formet etter NorgesGruppens egen dokumentasjon av
formatene. Det er noe annet enn å ha sett det virke.

Konkret uverifisert:

- **`format: "JSON"` sammen med `onskerSalgshistorikkPerHandel: true`.** Kilden vi
  bygget etter bestilte varelinjene som PDF og bare bonustransaksjonene som JSON. At
  varelinjene også kommer som JSON, er dokumentert av NorgesGruppen — men ikke sett.
  Går det galt, kommer dumpen uten `kjøpstransaksjoner_per_handel_per_vare.json`, og
  `importer` sier fra i stedet for å levere tomt.
- **Feltnavnene i dumpen.** Formen under er dokumentert, ikke observert:
  ```json
  {"dato": "12.03.2026", "kvitteringsnummer": "61719", "butikknavn": "...",
   "totaltBelop": "1218.65", "korttype": "ZTLD",
   "varelinjer": [{"varenavn": "...", "vareAntallVekt": "1.000", "vareBelop": "24.40"}]}
  ```
  Merk `totaltBelop` med t. Parseren kjenner igjen flere navn per felt, både denne
  varianten og plattform-API-ets, og rapporterer ukjente felter i `_meta` i stedet for
  å la dem forsvinne.
- **`/api/auth/session`-formen.** `accessToken` og `memberId` er dokumentert; verktøyet
  prøver `getToken` først uansett.
- **Hvor lenge kapslene faktisk lever**, og om `idsrv`-reserveveien virker i praksis.

`inspiser` finnes nettopp for dette. Den viser strukturen med **bare feltnavn, typer og
antall — ingen verdier**, så en rapport derfra kan deles for å få parseren oppdatert
uten at et eneste butikknavn eller beløp forlater maskinen din.

## Tester

```bash
python3 tests/test_trumf_kvitteringer.py
```

36 tester, ingen nettverk, ingen ekte kvitteringer. Dekker fornyingskjeden,
bestillingsformatet, dobbeltbestillingsvakten, nedlasting og parsing — og at
`importer` fortsatt virker uten sesjon.

## Vilkår

Trumfs medlemsvilkår sier ingenting om automatisert tilgang. Sanksjonene der gjelder
bonusmisbruk — «misbruk av fordeler eller forsøk på urettmessig tilegnelse av bonus».
Å be om innsyn i sine egne kvitteringer er ikke det.

Denne veien er uansett den ryddigste som finnes: innsyn og dataportabilitet er
rettigheter Trumf selv tilrettelegger for på profilsiden, og verktøyet sender nøyaktig
den forespørselen den siden sender.
