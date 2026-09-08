# oda-kvitteringer

Hent dine egne ordrer og kvitteringer fra [oda.com](https://oda.com). Ett kjørbart
skript, ingen avhengigheter utover Python 3.9+ stdlib.

Fungerer som skill i Claude Code og Codex, og som vanlig kommando i terminalen.

## Oppsett

Én gang per maskin:

```bash
bin/oda-kvitteringer oppsett
```

Den spør om e-post, passord (skjult) og en kontaktadresse til `User-Agent`-en.
Passordet lagres ikke — det brukes til ett innloggingskall, og bare
sesjonsinformasjonskapslene skrives til disk.

Ikke-interaktivt:

```bash
read -rsp "Oda-passord: " P; printf '\n'
printf '%s' "$P" | bin/oda-kvitteringer oppsett --epost din@epost.no \
  --kontakt din@epost.no --pass-stdin
unset P
```

Passordet går på stdin, aldri som argument — argumenter havner i `ps` og
skallhistorikk.

## Bruk

```bash
bin/oda-kvitteringer status              # er sesjonen i live?
bin/oda-kvitteringer ordrer --limit 10   # nyeste ordrer
bin/oda-kvitteringer ordre 12345678      # én ordre, normalisert
bin/oda-kvitteringer hent                # alle ordrer til disk, inkrementelt
bin/oda-kvitteringer raa 12345678        # uendret API-svar
bin/oda-kvitteringer logout              # glem sesjonen
```

JSON på stdout, diagnostikk på stderr, så det piper til `jq`:

```bash
bin/oda-kvitteringer ordre 12345678 | jq '.varelinjer[] | {navn, linjebelop}'
```

`hent` er inkrementell: ordrer som allerede ligger på disk hoppes over. Første
kjøring tar tid — den går med vilje rolig, ett kall i sekundet.

## Hvor ting ligger

| | |
|---|---|
| `~/.config/oda-kvitteringer/config.json` | e-post og kontaktadresse, `0600` |
| `~/.config/oda-kvitteringer/session.json` | sesjonsinformasjonskapsler, `0600` |
| `~/.local/share/oda-kvitteringer/ordrer/` | hentede ordrer, én JSON-fil per ordre |

Alt ligger **utenfor repoet**, og det er med vilje: dette repoet skal kunne gjøres
offentlig, og å gjøre et repo offentlig avslører hele git-historikken. Se
[`AUTH.md`](../../AUTH.md).

Stiene kan overstyres med `ODA_KVITTERINGER_CONFIG_DIR` og
`ODA_KVITTERINGER_DATA_DIR`.

Avinstallering: `bin/oda-kvitteringer logout`, og slett de to mappene over.

## Hva du får ut

```json
{
  "ordrenummer": "12345678",
  "dato": "2026-08-14",
  "maaned": "2026-08",
  "totalbelop": "1116.29",
  "varelinjer": [
    {
      "produkt_id": 9452,
      "navn": "Avokado modnet Chile / Spania/ Marokko",
      "antall": 2,
      "enhetspris": "14.95",
      "linjebelop": "29.90",
      "fra_oppskrift_id": null,
      "gruppe_indeks": 0
    }
  ],
  "_meta": {
    "priser_funnet": true,
    "antall_varelinjer": 1,
    "ukjente_varelinjefelter": []
  }
}
```

`produkt_id` er den eneste stabile identiteten — produktnavn endres, ID-en ikke.
Bruk den til «hvor mye har jeg brukt på X over tid».

Samme `produkt_id` kan opptre på flere linjer i én ordre: Oda skiller frittstående
varer fra varer lagt til via en oppskrift. `gruppe_indeks` og `fra_oppskrift_id`
holder dem fra hverandre, og begge linjene er ekte linjer på kvitteringen.

## Uverifisert: prisfeltene

Ordredetalj-endepunktet er ikke dokumentert av Oda — det er kartlagt av
[`gbbirkisson/mcp-oda`](https://github.com/gbbirkisson/mcp-oda), som bare bruker
`product_id`, `description` og `quantity` og derfor ikke viser om priser er med.

Verktøyet er bygget for begge utfall: det leter etter prisfelter under flere kjente
navn, og sier fra i `_meta` når det ikke fant noen — i stedet for å rapportere null.

**Første gang du kjører det:**

```bash
bin/oda-kvitteringer raa <ordrenummer> | jq '.items.item_groups[0].items[0]'
```

Ser du prisfelter som ikke er med, legg navnet inn i `LINE_TOTAL_KEYS` eller
`UNIT_PRICE_KEYS` øverst i skriptet. Det er ett listeelement.

## God oppførsel

[`oda.com/robots.txt`](https://oda.com/robots.txt) ber om identifiserende
`User-Agent` med kontaktinfo, eksponentiell backoff og respekt for `Retry-After`.
Verktøyet gjør alle tre. Ikke kjør flere kopier i parallell.

## Tofaktor

Odas dokumenterte innlogging er brukernavn og passord uten flere steg. Skulle
kontoen din kreve mer, stopper verktøyet og sier fra i stedet for å gjette.
Da er veien videre å logge inn i nettleser og lime sesjonen inn manuelt:

```bash
# i nettleseren: DevTools → Application → Cookies → oda.com → sessionid
mkdir -p -m 700 ~/.config/oda-kvitteringer
umask 077
cat > ~/.config/oda-kvitteringer/session.json <<JSON
{"cookies": {"sessionid": "DIN_VERDI", "csrftoken": "DIN_VERDI"}}
JSON
```

## Vilkår

Dette henter **dine egne** kjøp med **din egen** innlogging. Oda har ingen
publiserte bruksvilkår som forbyr det, og `robots.txt` beskriver tvert imot hvordan
de vil at automatisert trafikk skal oppføre seg.

Ordrehistorikk-endepunktet er likevel ikke i Odas publiserte API-dokumentasjon, så
det er ingen stabilitetsgaranti: det kan endre seg uten varsel. Det er en
driftsrisiko, ikke en juridisk.

Vil du ha en formelt sanksjonert vei, tilbyr Oda tidlig API-tilgang på forespørsel
(`api@oda.com`), og innsyn i egne persondata via `privacy@oda.com`.
