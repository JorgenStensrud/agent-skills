# Testing og verifisering av en PWA uten å ha telefonen i hånda

Prinsipp: alt som kan være en ren funksjon (tastaturmål, rulleminne, sveip,
versjonsavgjørelse, varselutløsere, markdown-tolking, layoutregning) **er** en ren
funksjon uten DOM, testet i `node --test`. Det som trenger en nettleser kjøres i
headless Chrome over CDP. Screenshots leses som bilder før man sier «ferdig».

## Headless Chrome over CDP

Rå CDP fra Node, uten Playwright. (I ett miljø feilet både Playwright og
chrome-devtools-mcp; andre steder virker de. Skriptene her trenger bare Chrome.)

`$CHROME --headless=new --disable-gpu --disable-extensions --no-sandbox
--remote-debugging-port=<port> --user-data-dir=<fersk> about:blank`, `WebSocket` finnes
i Node, `Runtime.evaluate` med `returnByValue: true, awaitPromise: true`. Skriptene
finner Chrome selv (`CHROME` overstyrer; på macOS også Chrome for Testing).

Fem feller, alle påkrevd for at bildet skal vise det du tror:

1. `Emulation.setDeviceMetricsOverride({ width: 390, height: 844, deviceScaleFactor: 1, mobile: true })`
   **etter** at sida er lastet (og igjen etter navigering), ellers legges sida ut på 980 px.
2. `Network.setBypassServiceWorker({ bypass: true })` eller fersk `--user-data-dir`,
   ellers serveres gammel JS. Vil du teste *oppgraderingen*, la SW-en være i fred og se
   `caches.keys()` bytte navn.
3. En tur innom `about:blank` før du navigerer: ny hash på samme URL laster ikke på nytt.
4. Velg targeten med `type === 'page'` fra `/json/list`; `--disable-extensions`.
5. **Ikke** `Emulation.setVisibleSize` i tillegg — da legges sida ut på 509 px igjen.

Mørk modus: `Emulation.setEmulatedMedia({ features: [{ name: 'prefers-color-scheme', value: 'dark' }] })`
før navigering — ellers verifiseres bare lys palett. Klipp helsidebilder ved 9 000 px;
større clip ga tomme eller enorme PNG-er. Skisser man vil vise på telefonen: legg PNG-en
under datamappa og server den fra en liten rute med validert navn.

Helside-bilde: `Page.captureScreenshot({ captureBeyondViewport: true, clip: { x: 0, y: 0, width: 390, height: scrollHeight, scale: 1 } })`,
ellers ganges skalaen med `deviceScaleFactor`. Rull gjennom sida først så late bilder
(`loading="lazy"`) er lastet.

**Virket ikke / spøkelse:** Chrome mobilemulering **utvider layout-viewporten ved
horisontal overflyt**. En scroll-stripe som klipper helt korrekt får `documentElement.scrollWidth`
til å måle for bredt, og alt `position: fixed; left: 0; right: 0` strekker seg med — bunnfanene
ser for brede ut. iOS Safari gjør ikke det. Mål aldri sidebredde uten å sjekke mot et
ekte skjermbilde.

Berøring: `Emulation.setTouchEmulationEnabled` + `Input.dispatchTouchEvent`
(`touchStart`/`touchMove`×n/`touchEnd`) for sveip; `navigator.share`, `setAppBadge`
stubbes med `Page.addScriptToEvaluateOnNewDocument`.

**Virket ikke:** `Input.synthesizeScrollGesture` i headless — den rullet ingenting og ga
en falsk «reprodusert»-konklusjon. Ekte bevis: `dispatchTouchEvent`-drag, gjerne med
gammel og ny versjon kjørende side om side på to porter (12/12 avbrutt vs. 0/11).

## Emulering er ikke en iPhone — si «målt» eller «antatt»

Chrome med iPhone-mål tester layout, ikke iOS-tastaturet (det ble simulert ved å lyve om
`innerHeight`), ikke safe-area (alltid 0), ikke P3-farger, ikke om Apple vekker
telefonen. Et skjermbilde fra telefonen er raskere enn å gjette videre i en emulator
som alt har bommet. Og verktøy brukeren ikke kan åpne på mobil (Lavish-sesjoner) er
ubrukelige til å vise noe — en PNG servert fra appen virket.

## Skriptene i `scripts/`

| Skript | Gjør |
| --- | --- |
| `skjerm.mjs <url> <png> [js] [--init js] [--mork]` | ett skjermbilde i 390 px, valgfri JS først (resultatet skrives ut); `--init` kjøres før sidas egen kode (sett `localStorage` før første tegning), `--mork` gir mørk modus |
| `skjerm-fake-strom.mjs <url> <png> <hendelser-json> [js]` | samme, med falsk `EventSource` som spiller av hendelser — chat i valgt tilstand uten agent |
| `frisk-sw.mjs <basis> <cachenavn> [ruter]` | fersk installasjon **med** SW: aktiv?, cachenavn, antall filer i skallet, konsollfeil på late ruter |
| `konsoll.mjs <basis> [ruter]` | sveip over ruter med SW på: konsollfeil, HTTP ≥ 400, bilder som ikke lastet |
| `ios-sjekk.mjs <basis>` | iOS-runden mot en kjørende server: faner, rulleminne, sticky, bunnark, sveip med ekte berøring, Dynamic Type, ikonmerke, kalender (tilpass rutene) |
| `nyversjon-e2e.mjs <appmappe> <port>` | ende til ende: app oppe, «ny utrulling», sida bytter selv ved forgrunn, «Hent den» under bruk (tilpass miljøvariablene i toppen) |
| `skall-til-sw.mjs <dist> <sw.js>` | ikke en test, men bygget: hasher byggefilene til et cachenavn og skriver `CACHE` og `SKALL` inn i `sw.js`; feiler hvis plassholderne mangler (oppdatering.md avsnitt 6) |

Sjekk at PNG-fila faktisk finnes og ikke er tom før du leser den. Ett verktøy meldte
«lagret» uten å ha skrevet noen fil.

Måleskriptet i reiseapp (`verktoy/ux-skjermer.mjs`) gir i tillegg `maal.json` per rute:
sidehøyde, trykkflater under 44 px, skriftstørrelser, overskrifter. **Mål før og etter**
hver runde og skriv tallene i planen (Utforsk 36 509 → 2 245 px, 149 → 0 små flater).

## Rene funksjoner som ble testet (kopier mønsteret)

- `maalTastatur` — begge iOS-variantene av tastatur, knip-zoom, uten fokus.
- `lagRulleminne` — tilbake vs. videre, fanetrykk.
- `sveipRetning/sveipUtfall/sveipForskyvning` — kantsone, rulling, terskler.
- `avgjor({ skall, server, swVedLast, swNaa })` — de fire utfallene.
- `erModulfeil(melding)` — Safari- og Chrome-tekstene.
- `UTLOSERE.*`, `modne`, `ingress` — klokka i riktig tidssone, stille timer, dedupe.
- `tolk/tolkLinje` — markdown uten falske treff, farlige URL-er avvist.
- `naerBunn`, `merkeTall`.
- Layout-generatorer (fotoboka) med injiserbare avhengigheter (`bildeUrl`, `maal`, `dager`),
  så sidebrytning, partall og escaping testes uten Chrome. Generert SVG: `!svg.includes('NaN')`
  — en projeksjon som deler på null gir ellers en «gyldig» tom SVG.
- Falsk EXIF med sharp: `.withMetadata({ exif: { IFD2: { DateTimeOriginal, OffsetTimeOriginal } } })`;
  en tekstfil med `.jpg`-navn skal gi `null`, ikke kaste.
- Oppstartsmigreringer: skriv en «gammel» `reise.json` til en temp-mappe, spawn en server
  til på `PORT + n`, poll API-et — så dekkes både minnet og disken.
- **Service workeren i node:** `sw.js` er et vanlig skript. Kjør det i
  `vm.runInNewContext(kode, { self: { addEventListener() {} }, location: { origin: 'http://x' }, Headers, Response })`,
  så ligger de rene hjelperne (`fraLager`, hvilke cacher som beholdes, hvilke stier som
  er bilder) i konteksten og kan testes uten nettleser.
- **Falsk push:** når et miljøflagg peker på en fil, skriver serveren hver push som en
  JSON-linje der i stedet for å sende. Et endepunkt som slutter på `/dod-410` svarer
  som et dødt abonnement, så oppryddingen testes også.
- **Chatten uten innlogging:** en demo-modell som svarer med ferdige svar gir ekte
  skjermbilder av chatten, med strømming og verktøylinjer, uten konto og uten kvote.

Agentloopen testes mot Pi sin faux-provider (ingen nettverk), gjennom samme
samtale-modul som drift bruker; API-et med en spawnet server mot tom datamappe.
Flaking lå i testoppsettet (agent-oppvarming ved oppstart, for kort ventetid) — ikke i
appen; slå oppvarmingen av i test (`REISEAPP_INGEN_OPPVARMING=1`) og gi etterfylling
tid.

## Testfeller som ga falske grønne (eller røde)

- `npm test | tail -4` viser bare «cancelled/skipped/todo/duration» — en rød pakke ble
  rullet ut som «verifisert». Se på `# pass`/`# fail`-linjene.
- `set -o pipefail` + `grep -q` fikk grønne tester til å se røde ut (grep lukker røret).
  Skriv til fil, grep etterpå.
- Node sin `fetch` pakker ut gzip selv: bruk rå `node:http` for å se `content-encoding` og
  bytes. **Virket ikke:** absolutt terskel (`< 30 000`) — røk da seeden vokste; test forholdet
  (`komprimert < rå × 0,45`). Test at strømmen *ikke* komprimeres, og `res.destroy()` i
  callbacken, ellers henger testen på en uendelig strøm.
- Sti-traversering med URL-kodet skråstrek (`/mini/bilder/..%2F..%2Fserver.js` → 404):
  Express dekoder `%2F` før `:fil`, så regexen ser trygg ut uten testen.
- Tester på generert eller kuratert innhold sjekker **form**, ikke antall som en
  kuratering lovlig kan redusere til null (**Virket ikke:** `topp.length > 0`): ingen
  `null`-felt, tekster over 40 tegn, bildestier som matcher, klokkeslett `^([01]\d|2[0-3])\.[0-5]\d$`.
- Tidsavhengige tester trekker seg når de ikke gjelder lenger (`if (til < iDag) return`);
  en test som blir rød etter turen er en test ingen tror på.
- Flere headless Chrome samtidig trenger hver sin tilfeldige port, og targeten velges
  først etter opptil 100 × 150 ms venting.
- `node --test` kjører testfilene **parallelt**. Filer som starter servere på faste
  porter, krasjer av og til i hverandre. Gi hver fil sitt eget portområde, eller kjør
  med `--test-concurrency=1`.
- Testen regnet «i morgen» i UTC, verktøyet i Roma-tid: ulik dag rundt midnatt.
- Miljøhygiene: 28 lekkede headless Chrome-prosesser (`pkill -f "user-data-dir=/tmp/chrome-"`),
  gamle dev-servere som serverte gammel kode (drep etter PID fra `ss -ltnp`, ikke
  `pgrep -f` som treffer bash-wrapperen). Dev-server mot **kopi** av prod-data på egen
  port — og likevel skrev en test et «nett-test»-ønske inn i prod. Sjekk `REISEAPP_DATA`
  før hver skrivende test.
- Mål ytelse på strupet nett (`Network.emulateNetworkConditions`: 300 ms RTT, 4 Mbit),
  det er der telefonene er.

## Sjekkliste før «ferdig»

1. `npm test` grønt.
2. Skjermbilde(r) av det som ble endret, **lest** som bilde — ikke bare tatt.
3. `frisk-sw.mjs` mot produksjon etter deploy som rører `sw.js`/skallet.
4. `konsoll.mjs` over rutene: «ingen feil funnet».
5. `curl /api/versjon` viser ny hash; `curl /sw.js | head -1` viser nytt cachenavn.
