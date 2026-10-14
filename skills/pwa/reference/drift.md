# Drift: deploy, versjon, ytelse og robusthet

## Deploy uten byggesteg

- **`git archive`, ikke `git pull` på verten.** Kopien av lokal `HEAD`:
  `git archive --format=tar HEAD | sudo tar -x -C /srv/app/app`, `chown -R app:app`,
  `systemctl restart app.service`, `npm ci --omit=dev` bare når avhengigheter endres.
  Export-subst (`versjon.txt`, `public/index.html`) fylles bare av `archive`.
- Sjekk `hostname` før et deploy-skript som ssh-er: står du **på** verten, feiler ssh
  til seg selv — gjør stegene direkte med sudo.
- **`localhost:PORT` på verten er produksjon** — samme data som telefonene. Test
  skriving mot en egen instans med `PORT=3403 APP_DATA=/tmp/kopi node server.js`.
- Verifiser: `curl localhost:PORT/api/versjon` = ny hash, `curl …/sw.js | head -1` =
  nytt cachenavn, så `scripts/frisk-sw.mjs`.
- Fast-forward `main` etter vellykket deploy fra en worktree-gren.
- `tar -x` sletter aldri: fjernede filer blir liggende og servert. Pakk ut i ny mappe og
  bytt, eller slett eksplisitt. Behold forrige som `app-forrige-<sha>` for rullback.
- Ikke-utrullede filer som ikke er i git (380 MB arbeidsfiler) hoper seg opp på verten
  på samme måte.
- Etter `systemctl restart`: poll `/api/health` (8 × 1 s) før du leser `/api/versjon`,
  ellers svarer en server som ikke lytter ennå, og «utrullingen» ser mislykket ut.
- Verktøy kjørt med `sudo` etterlater root-eide filer i repoet: `chown -R "$(id -u):$(id -g)"`
  før `git add`. En ubemannet runde logger til én fil, kjører `npm test` til fil og ruller
  bare ut når `^# fail 0` treffer; røyktest etterpå teller det som ble endret via API-et.
- Rydd spike- og debug-skript ut *før* commit.

## systemd-enheten som overlever at noe annet løper løpsk

Verten er også utviklingsmaskin; en lekk prosess spiste 9,5 GB og appen var borte i
minuttene før kjernen tok den. Derfor:

```ini
OOMScoreAdjust=-500     # kjernen tar det andre først
MemoryLow=256M          # de første 256 MB swappes ikke ut
MemoryMax=1G            # lekker vi, er det vi som dør — ikke verten
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/srv/app/data
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
Restart=always
RestartSec=5
```

Konsekvens av `ProtectSystem=strict`/`ProtectHome`: alt appen skriver (cache av
småbilder, PDF-bygging, Chrome-profil for PDF) må ligge under `ReadWritePaths`.
Chrome for PDF: sett `HOME` og `--user-data-dir` under datamappa.

## HTTPS uten offentlig adresse

`tailscale serve --bg --https=5443 http://127.0.0.1:3210` → `https://<vert>.<tailnet>.ts.net:5443`
med ekte sertifikat. iPhone krever HTTPS for service worker og push. Ingen auth i
appen: tailnettet er grensen; hold den utenfor en offentlig reverse proxy.

## Ytelse på 5G via relé

- Turen tegnes fra kopi (localStorage) med en gang; fersk i bakgrunnen.
- `modulepreload` på det første skjermen trenger.
- Småbilder fra serveren (640 px JPEG, lages ved første forespørsel, `immutable` i
  sju dager), lat lasting (`loading="lazy" decoding="async"`) på alt under folden.
- gzip på alt unntatt strømmer. 21 MB → 0,6 MB per runde.
- Agenten varmes opp etter oppstart, så første trykk på chatten ikke venter fire
  sekunder (kan slås av i test).
- Alle visningene importeres i ro etter første tegning — også en versjonsgaranti (se
  oppdatering.md).

## Delte data mellom to telefoner uten websockets

- Én `data/` per vert; brukerdata i `reise.json` + filer, kuratert innhold i seed som
  legges på ved hver henting (så en redeploy oppdaterer innhold uten migrering). Alt
  brukerne eier må ligge i datafila; legges det i seeden, blir det overskrevet.
- Nye lister som kommer til etter seeding: `req.tur.fraser ||= []` i middleware.
- Skrivinger som feiler uten nett køes i minnet og sendes når nettet er tilbake — ikke
  i localStorage (en gammel fane skal ikke sende gamle endringer inn i delte data).

## Versjonssynlighet

- Fot nederst på en samleside: «versjon 87d7837 · 2026-09-15» + «Hent ny versjon».
- `/api/versjon` og `/sw-versjon` (se oppdatering.md).

## Ting som gikk galt utenfor koden

- **Git-treet vokste til 770 MB** med råbilder i commits; `git filter-repo` ned til
  70 MB, råbilder gitignored (historikken divergerer → `push --force`, brukerens valg).
- **Sikkerhetskopi** lå på samme disk og var ni dager gammel mens 42 MB brukerdata kom
  til; reserveverten svarte ikke uten at noe sa fra. Kopier til en annen maskin, og
  overvåk den.
- **DNS på verten:** `tailscale --accept-dns=false` gjorde at maskinen ikke slo opp
  `.ts.net`-navn selv (telefonene med MagicDNS var upåvirket). Bruk `localhost` på verten.
- **SSRF** overalt der appen tar imot en adresse (hente PDF, hente bilde, push-endepunkt):
  slå opp vertsnavnet, nekt loopback/private/link-local, følg omdirigeringer for hånd
  med samme sjekk per hopp, og begrens appens egne stier til bildemappene. Konkret:
  også **100.64.0.0/10** (CGNAT — Tailscale-adressene, `https://100.x.y.z/` er appens egen
  vert), 0/8, 224+, `::ffff:`-mappet IPv4, IPv6 `fc/fd/fe80/ff`, og navnene `localhost`,
  `*.local`, `*.internal`; bare `https:` som skjema (Python `urlopen` godtar `file://`);
  `redirect: 'manual'` i en løkke på høyst 4 hopp; størrelse sjekket både på
  `content-length` og etter `arrayBuffer()`; én miljøvariabel skrur hele vakten av i test.
  Filnavn fra høstede felt går gjennom en slug, aldri feltet.
- **DNS-rebinding** (navnet svarer offentlig ved sjekken og privat ved tilkoblingen)
  stenges bare ved å sjekke adressen det faktisk kobles til. Ikke `fetch`: hent over
  `node:http(s)` med et eget `lookup` som slår opp navnet, nekter hvis *noen* av
  adressene er private, og gir tilkoblingen nettopp de sjekkede adressene. En IP i
  URL-en slås ikke opp, så den sjekkes for seg. `agent: false` gir en fersk agent per
  forespørsel: ingen gjenbrukt forbindelse, og ingen proxy fra miljøet
  (`HTTP_PROXY`/`NODE_USE_ENV_PROXY` gjelder den globale agenten). IPv6 i alle former
  må med: IPv4-mappet (`::ffff:7f00:1` er 127.0.0.1), NAT64 `64:ff9b::/96`, 6to4
  `2002::/16` og Teredo `2001::/32` bærer en IPv4-adresse inni; enklest er å nekte alt
  utenfor `2000::/3` og sjekke de innbakte IPv4-adressene. La URL-tolkeren normalisere
  desimale og heksadesimale IP-er (`http://2130706433/`, `0x7f.1`) før sjekken.
- **Les kroppen som strøm med tak**, ikke `arrayBuffer()` og så mål: avbryt når taket
  er nådd, og pakk ut gzip/brotli selv med samme tak på det utpakkede, ellers er en
  liten gzip-bombe nok.
- **LLM-JSON må ikke spres sist** over betrodde felt (`{ kode, url, ...json }`): modellens
  svar kan overskrive `url` med `javascript:`; plukk felt eksplisitt, og la `el()`/en
  `trygtHref` avvise alt annet enn `https?:`, `#/`, `tel:`, `mailto:` — seed-data går utenom
  API-validering.
- **Allowlist-oppslag med objekt** (`INNSTILLINGER[navn]`) er truthy for `__proto__` →
  500; bruk `Object.hasOwn`. Objekter nøklet på brukerinput trenger nøkkelregex
  (`^\d{4}-\d{2}-\d{2}$`). Valgfrie felt som skal kunne fjernes: `delete` når `undefined`,
  ellers blir nøkkelen liggende.
- **Ytelse, målt på 300 ms RTT / 4 Mbit:** kaldstart Hjem 2,9 → 1,4 s, album 3,3 MB →
  183 KB, Spør 4,2 → 0,4 s, hele runden 20,9 → 0,6 MB. Årsaken var sju telefonbilder à
  3–5 MB i original på Hjem; alt annet ventet i kø bak dem.
- **PDF på verten:** HTML → `Page.printToPDF` over CDP (`preferCSSPageSize`), `pdftoppm
  -r 50` for sidebilder, skrifter via `@font-face` med `file://` fra `node_modules`
  (sjekk med `pdffonts`), bilder krympet til 2000 px først. Chrome kjører under
  systemd-herdingen med `HOME` og profil under datamappa.
- **Bilder fra iPhone:** EXIF `DateTimeOriginal` + `OffsetTimeOriginal` gir «tatt» med
  sone; skjermbilder og Messenger-bilder mangler EXIF → opplastingsdag som reserve.
  Etterfylte felt skiller «lest, fant ingenting» (`null`, les ikke igjen) fra «feilet»
  (`null` på hash → prøv ved neste start) og «aldri lest» (`undefined`).
- **Småbilder**: `sharp(fil).rotate().resize({ width: 640, height: 640, fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 78, mozjpeg: true })`
  — `.rotate()` uten argument bruker EXIF-orienteringen (iPhone-bilder ligger sidelengs).
  Lages rett etter opplasting (fire-and-forget etter 201), slettes med originalen, skrives
  atomisk (`.pid.ny` + `renameSync`) siden Hjem og albumet ber om samme bilde samtidig.
  Ruta slår opp mappa i en allowlist og filnavnet mot `^[\w.-]+$`.
- **`lagre()` skriver `reise.json.tmp` og `rename`-er**: en etterfylling i bakgrunnen og et
  vanlig kall kan lagre samtidig uten halvskrevet fil.
- **Langvarig jobb** (PDF 30–120 s): `POST` → `202 { status: 'bygger' }`, et
  modulnivå-promise som lås mot dobbelt bygging, siste feil husket i status; klienten poller
  hvert 3. sekund *bare* mens `bygger` og stopper når `!boks.isConnected`. «Lag på nytt»
  sender `{ tving: true }`. Artefakten har en `signatur()` = sha1 av **alt** som tegnes +
  `LAYOUT_VERSJON`; status `gammel` når den avviker — plan og vær var med i boka men ikke i
  signaturen, og snacksene ble stående gamle.
- Chrome for PDF fra `file://`: `--allow-file-access-from-files --disable-dev-shm-usage`,
  vent på `readyState === 'complete' && alle bilder complete` før `Page.printToPDF` (ellers
  mangler bilder på tilfeldige sider); variable skrifter trenger `format('woff2-variations')`
  + `font-weight: 200 800`.
- Server-cachet værvarsel trenger `past_days` så snart en side ser bakover, og
  `VAER_VERSJON` bumpes i samme commit.
- **Herdet tjeneste som trenger en annen brukers hjem** (venv, innloggede kontoer): la
  appen skrive en bestillingsfil i `<data>/<jobb>-bestillinger/`, la en systemd
  **path-enhet** som riktig bruker plukke den opp, og la jobben skrive status til
  `<data>/<jobb>-status.json`. Én om gangen; et miljøflagg sier om verten *har* en høster.
- Agentmodulen (Pi, 96 pakker) lastes lat første gang noen spør — feiler importen, virker
  resten av appen. `setInterval(...).unref()` på rydding og oppvarming, så prosessen kan
  avslutte. Modell og bryterverdier overstyres med miljøvariabler, så en vri i drift ikke
  krever utrulling.
- Serveren sprer kuratert innhold **sist** (`{ ...tur, ...innhold }`): brukerdata og seed
  må ha disjunkte feltnavn, ellers overskrives det brukerne eier ved hver henting.

## Klokke og tidssone

Alt som handler om «nå» (varsler, morgenmelding, «i dag») regnes i brukernes
tidssone med `Intl.DateTimeFormat(…, { timeZone })`, ikke serverens. En systemprompt
som lages én gang per sesjon kan ikke bære klokka — legg klokkeslettet i det som
hentes ved hvert spørsmål.
