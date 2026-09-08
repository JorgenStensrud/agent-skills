# Skills med pålogging

Hvordan et verktøy her autentiserer mot en tjeneste, hvor legitimasjonen bor, og hvordan
det gjøres slik at koden kan ligge offentlig uten at hemmeligheter følger med.

`README.md` dekker det mekaniske ved en skill. `OPPSETT.md` dekker riggen. Dette dokumentet
dekker det som gjenstår: pålogging.

> `oda-kvitteringer` og `trumf-kvitteringer` bor ikke lenger her — de er flyttet til
> [`digital-kjoleskap`](https://github.com/JorgenStensrud/digital-kjoleskap), som har sin
> egen `AUTH.md` med den delen av denne oppskriften som gjelder dem. De står fortsatt som
> presedens under, fordi de er de eneste utbygde eksemplene på to av mønstrene.

> Filnavnet er `AUTH.md` og ikke `PÅLOGGING.md` med vilje. macOS lagrer `å` i filnavn
> annerledes enn Linux (NFD mot NFC), og et repo som synkes mellom Mac og matebook får da
> filen til å se endret ut på begge maskiner samtidig. Æ, ø og å hører hjemme i innholdet,
> ikke i filnavn som skal krysse maskingrenser.

---

## 1. Den ene regelen som ikke kan ettermonteres

**Ingen legitimasjon, ingen personopplysninger og ingen hentede data i repoet. Noen gang.
Uansett hvor privat det er der og da.**

Grunnen er ikke forsiktighet, den er mekanisk:

> Å gjøre et repo offentlig avslører hele git-historikken, ikke bare siste versjon.

Enhver commit, enhver slettet fil, enhver rettet tabbe ligger der og hentes ut med
`git log -p`. Det betyr at «vi rydder før vi publiserer» ikke virker: å slette en fil og
committe slettingen fjerner ingenting — det legger bare til en commit som sier at filen ble
borte. Innholdet er fortsatt utsjekkbart fra forrige commit.

Å faktisk fjerne noe krever `git filter-repo`, som skriver om hver eneste commit-hash. Det
betyr tvungen push, ødelagte kloner på andre maskiner, og — viktigst — **hemmeligheten må
uansett roteres**, fordi du ikke kan vite om den ble lest i mellomtiden. Historikkomskriving
er skadebegrensning etter et uhell, ikke en arbeidsmetode.

Regelen er absolutt, og det er derfor den er billig: den fjerner spørsmålet «er dette trygt å
committe?» fra hver eneste commit.

Den gjelder også det som ikke føles som en hemmelighet: en testfil med en ekte kvittering, et
eksempelsvar med butikknavn og dato, en feillogg med et medlemsnummer. Kvitteringsdata er
personopplysninger — de sier hvor du handler, når, og hva du spiser.

### Todelingen

Skillet går ikke mellom to repoer. Det går mellom repoet og filsystemet utenfor det:

```
  REPO (publiseringsklart fra commit 1)      UTENFOR REPO (privat, synkes aldri)
  ────────────────────────────────────       ──────────────────────────────────────
  skills/<navn>/                             ~/.config/<navn>/
    SKILL.md          instruksjoner            config.json    valg              0600
    bin/<navn>        hjelpeskriptet           session.json   informasjonskapsel 0600
    README.md         for andre enn deg
                                             ~/.local/share/<navn>/
                                               ...            hentede data
```

Et privat konfigurasjonsrepo ved siden av et offentlig koderepo hadde betydd to steder å
committe og to historikker å holde rene — og fortsatt nøyaktig samme regel. Du betaler
kompleksitet uten å kjøpe sikkerhet.

Legitimasjonen ligger utenfor arbeidstreet. Ikke fordi `.gitignore` skjuler den, men fordi
git ikke ser den i det hele tatt. Det er den eneste beskyttelsen som ikke kan omgås av en
distré `git add -A`.

**Konsekvens for riggen:** legitimasjon synkes ikke mellom Mac og matebook, siden `rsync`-en
i `OPPSETT.md` bare tar repoet. Det er riktig — det er samme modell som «Login: ❌ per konto
per maskin» i tabellen der. Førstegangsoppsett kjøres én gang per maskin, og det bør stå i
`SKILL.md` så det ikke oppleves som en feil.

**Publisering senere:** `git subtree split --prefix=skills/<navn>` gir et nytt repo med bare
den mappas historikk. Det er trygt **utelukkende** fordi regelen over har vært fulgt hele
veien.

### Vernet i repoet

`.gitignore` dekker legitimasjon, sesjonsfiler, nøkler og hentede data. `scripts/scan-secrets`
kjøres av `hooks/pre-commit` og blokkerer det som staged.

Skanneren er bevisst smal — den treffer bare leverandørprefiksede tokener, privatnøkkel-armering
og filnavn som aldri skal committes. Den prøver **ikke** å matche generiske `password = ...`,
fordi ekte dokumentasjon er full av dem, og hver falske positiv lærer deg å hoppe over hooken.
En guard som ropes ulv med, blir omgått, og en omgått guard er verdt null.

Trenger du et bevisst eksempel som treffer et mønster: sett `scan-secrets: ignore` på linjen.

---

## 2. Arkitektur: skill + kjørbart hjelpeskript

```
          ┌───────────────────────────┐
          │  bin/<navn>  (CLI)        │   ← all oppførsel bor her
          │  JSON på stdout           │
          └─────────────┬─────────────┘
                        │
          ┌─────────────┴─────────────┐
          │                           │
    ┌─────┴──────┐            ┌───────┴────────┐
    │  SKILL.md  │            │  terminalen    │
    │  når og    │            │  deg selv,     │
    │  hvordan   │            │  uten AI       │
    └────────────┘            └────────────────┘
```

**Hvorfor ikke bare skrive det i `SKILL.md`:**

En skill er markdown en agent leser. Legger du logikken der, blir den *tolket* på nytt hver
gang — og to kjøringer av samme oppgave kan gjøre forskjellige ting. Et hjelpeskript kjører
likt hver gang, kan feilsøkes med `bash -x` eller en stacktrace, og kan kjøres uten AI i det
hele tatt.

`SKILL.md` blir da kort: når verktøyet er riktig valg, hvilke kommandoer som finnes, og hva
den skal gjøre når noe feiler. Ingen forretningslogikk.

**Strukturert utdata er ikke pynt.** JSON på stdout betyr at en agent kan lese resultatet uten
å parse prosa, at du kan pipe det til `jq`, og at feil kan skilles fra tomme resultater
maskinelt. Skriv diagnostikk til stderr, data til stdout, og la exit-koden bety noe.

**Når ville MCP vært riktig i stedet?** Når agenten skal føre en samtale med tjenesten — mange
små kall i én tankerekke, der typede verktøy og vedvarende tilstand betaler for prosessen. En
satsvis uthenting er ikke det: det er ett kall som skriver en fil. Da er en ekstra prosess å
holde i live ren kostnad.

---

## 3. Påloggingsmønstrene

Fire mønstre dekker praktisk talt alt. For hvert: hva brukeren må gjøre første gang, og hva
som skjer når tokenet går ut.

### API-nøkkel

Brukeren henter en nøkkel fra tjenestens nettside og limer den inn én gang.

- **Første gang:** logg inn i nettleser, generer nøkkel, lim inn.
- **I drift:** ingenting, til nøkkelen tilbakekalles. Da er feilen tydelig (401) og fiksen er
  å lime inn en ny.
- **Presedens her:** `send-mail`. `RESEND_API_KEY` leses fra miljøet med en eksplisitt sjekk
  og en hjelpsom feilmelding.
- **Enklest å leve med.** Velg dette når tjenesten tilbyr det.

### OAuth/OIDC med omdirigering

Brukeren sendes til tjenestens innloggingsside, godkjenner, og sendes tilbake til en lokal
port med en kode som byttes mot tilgangstoken og fornyingstoken.

- **Første gang:** nettleser åpnes, vanlig innlogging — inkludert tofaktor, som tjenesten
  håndterer selv. Det er den store fordelen.
- **I drift:** tilgangstoken varer minutter til timer, fornyingstoken uker til måneder.
  Fornyes stille. Når fornyingstokenet dør, må brukeren gjennom nettleseren igjen.
- **Presedens her:** `sentry-cli`, som lar leverandørens egen CLI eie det: *«Never store or
  log authentication tokens — use `sentry auth login` and let the CLI manage credentials.»*
  Riktig instinkt — ikke bygg det selv når leverandøren har gjort det.
- **Kostnaden:** PKCE, lokal omdirigeringslytter, fornyingslogikk. Betydelig mer kode.

### Sesjonsinformasjonskapsel

To varianter, og forskjellen betyr mye.

**(a) Kopiert fra nettleseren.** Brukeren finner `Authorization`- eller `Cookie`-verdien i
utviklerverktøy og limer den inn.

- Klossete, men helt uten risiko for å automatisere noe.
- Dør når sesjonen dør, uten mulighet for fornying.
- **Bruk til:** engangsuttrekk og utforskning. For dårlig ergonomi til noe som kjøres jevnlig.

**(a2) Kopiert én gang, deretter selvfornyende.** Samme innliming, men verktøyet lagrer
*sesjonskapslene* og bytter dem inn i et ferskt tilgangstoken ved hvert kall.

- **Første gang:** som (a) — lim inn fra utviklerverktøyene.
- **I drift:** tokenet fornyes stille så lenge sesjonskapselen lever. Har tjenesten en
  langlevd innloggingskapsel på identitetsdomenet, kan verktøyet dessuten følge
  OAuth-omdirigeringene og skaffe seg en helt ny sesjon uten at brukeren merker noe.
- **Presedens:** `trumf-kvitteringer`, nå i `digital-kjoleskap`. Trumf har SMS-tofaktor, så
  (b) er utelukket — men innlimingen trengs likevel bare én gang per maskin.
- **Bruk til:** tjenester der innloggingen må skje i nettleseren, men resten kan
  automatiseres. Det er de fleste av dem.

**(b) Verktøyet logger inn selv** mot tjenestens innloggingsendepunkt og tar vare på
informasjonskapselen.

- **Første gang:** brukeren oppgir brukernavn og passord én gang.
- **I drift:** informasjonskapselen gjenbrukes. Ved 401/403 må brukeren logge inn på nytt.
- **Passordet lagres aldri.** Det brukes til ett innloggingskall, og bare sesjonen skrives til
  disk.
- **Passordet tas inn på stdin, aldri som argument.** Argumenter lekker til `ps` og
  skallhistorikk.

Dette er mønsteret `oda-kvitteringer` bruker, nå i `digital-kjoleskap`.

### Enhetskoblet token

Brukeren får en kode å taste inn fra en annen enhet (`gh auth login`-mønsteret). Langlevd,
fornyes stille. Krever støtte i tjenesten.

---

## 4. Hvor hemmeligheten bor

| Sted | Vurdering |
|---|---|
| `.env` **i repoet** | **Nei.** Ett `git add -A` fra å ligge i historikken permanent. |
| Miljøvariabler | Greit for tjenerprosesser. Interaktivt må noe sette dem — som regel en fil, og da er du tilbake til å velge hvor *den* bor. |
| `~/.config/<navn>/` med `0600` | **Anbefalt.** Utenfor repoet, XDG-konvensjon, likt på Linux og Mac, ingen avhengigheter, virker over SSH og headless. |
| Systemets nøkkelring | Sterkest på papir. Men `secret-tool` mot Keychain er to ulike verktøy, den krever en ulåst økt (feiler over SSH), og gir én bruker på én maskin samme beskyttelse som `0600` mot alt annet enn en angriper som allerede kjører som deg. Kompleksitet uten gevinst her. |

**Sett tillatelsen ved oppretting, ikke etterpå.** `touch` og deretter `chmod` har et vindu der
filen er verdenslesbar:

```python
os.makedirs(config_dir, mode=0o700, exist_ok=True)
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
```

---

## 5. Førstegangsoppsett som gjør verktøyet brukbart for andre

Dette er det som skiller «virker for meg» fra «kan publiseres». Alt personlig kommer fra
oppsettet, ikke fra koden.

`bin/<navn> oppsett` bør:

1. Opprette `~/.config/<navn>/` med `0700`.
2. Spørre om **brukernavn/e-post** — aldri hardkodet.
3. Lese **passord fra stdin med slått av ekko**, aldri som argument.
4. Utføre innloggingen og lagre **kun sesjonen**.
5. Verifisere med ett lesekall, og si tydelig ifra hvis det ikke virket.
6. Skrive hvor ting havnet, så brukeren vet hva som skal slettes ved avinstallering.

`SKILL.md` sier så: *«Mangler sesjonen, kjør `bin/<navn> oppsett` og stopp. Ikke spør brukeren
om passord i chatten.»* — siste setning er viktig: et passord skrevet i chatten havner i
økttranskriptet, og `OPPSETT.md` sier allerede at transkripter aldri skal inn i git.

---

## 6. Feilhåndtering som betyr noe

Fellesnevneren: **verktøyet må aldri returnere tomt når det egentlig feilet.** Et tomt
resultat leses som «ingen data i perioden», og det er en usann påstand om brukerens liv. Alle
fire tilfellene under er varianter av den ene feilen.

### Utløpt sesjon

Det farlige er at mange API-er svarer `200 OK` med en tom liste når sesjonen er borte, fordi
de behandler deg som anonym.

**Regel:** sjekk at du faktisk er innlogget *før* du stoler på et tomt resultat. Og si hva
brukeren skal gjøre:

```
Sesjonen mot Oda er utløpt. Kjør:  oda-kvitteringer oppsett
```

Ikke `Error: 401`.

### Tofaktor

Når et innloggingssvar inneholder noe verktøyet ikke forstår — et utfordringssteg, en
omdirigering til verifisering — skal det **stoppe og si det**, ikke gjette seg videre.
Fallback er å be brukeren logge inn i nettleser og lime inn sesjonen.

**Automatiser aldri en engangskode.** Det gjør en sikkerhetsmekanisme til teater, og et
skript som ber om SMS-koden din er umulig å skille fra svindel neste gang noen faktisk prøver.

### Endret format hos tjenesten

I prioritert rekkefølge:

1. **Bruk JSON-endepunkter framfor sideskraping.** Sidehydrering er en implementasjonsdetalj
   som endrer seg når frontend-teamet bytter rammeverk. Et JSON-endepunkt har en kontrakt.
2. **Sjekk formen, ikke bare at det kom noe.** Mangler et forventet felt, er det en
   formendring — ikke en tom ordre. Si det, og si hva du faktisk fikk:
   ```
   Oda svarte 200, men ordre 12345678 mangler items.item_groups.
   API-formatet har trolig endret seg. Fikk nøklene: items, status, delivery
   ```
   Brukeren vet da at det trengs en oppdatering, ikke at han sluttet å handle.
3. **Ikke gjør pagineringsfeil om til stillhet.** En gjentatt paginerings-URL er en feil, ikke
   en grunn til å løkke — ellers får du delvise data som ser komplette ut.

### Ratebegrensning og god oppførsel

Les tjenestens `robots.txt` før du skriver klienten. Odas sier rett ut hva de forventer:
identifiserende `User-Agent` med kontaktinfo, eksponentiell backoff, respekter `Retry-After`.

Følg det bokstavelig. Det er både høflig og beskyttende: en identifiserbar klient som oppfører
seg pent blir kontaktet før den blir blokkert. En anonym klient som hamrer, blir bare blokkert.

---

## 7. Å be om dataene framfor å hente dem

GDPR artikkel 15 gir deg rett til innsyn i egne data, og de fleste tjenester har en
selvbetjent eksport. **Vurder alltid den veien først** — ikke av forsiktighet, men fordi den
ofte gir *mer* data for *mindre* arbeid.

Konkret eksempel: Trumf viser 12 måneder på nettsidene, men lagrer kvitteringer i tre år.
Innsynsdumpen gir altså tre ganger så mye. `trumf-kvitteringer` velger derfor innsynsveien
framfor å skrape kvitteringssidene.

Og merk hvor lett det er å ta feil om hva som må gjøres for hånd: skillen ble først levert som
en ren parser, fordi bestillingen så ut som et skjema du måtte klikke deg gjennom. Det var den
ikke — skjemaet sender en helt vanlig `POST` som et hvilket som helst verktøy kan sende. **Se
etter kallet i nettverksfanen før du konkluderer med at noe er manuelt.** Hele forskjellen
mellom «be brukeren gjøre det» og «gjør det» kan ligge der.

Ventetiden forsvinner ikke av at bestillingen automatiseres — Trumf har inntil 30 dager på
seg. Et verktøy for en asynkron rettighet må derfor **huske at det har bestilt** og kunne
svare på «er den klar?» dager senere, ikke vente aktivt i en løkke.

Motsatt for Oda: ingen selvbetjent eksport, bare en manuell forespørsel til `privacy@oda.com`
per gang. Det duger til et engangsuttrekk, ikke til noe som kjøres jevnlig — og Oda har
allerede en dokumentert, autentisert vei til de samme dataene.

Regelen er altså ikke «alltid innsyn», men: **sjekk hva innsyn faktisk gir før du bygger en
klient.** Noen ganger er det ferdig bygget for deg.
