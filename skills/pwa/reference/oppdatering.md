# Oppdatering: få den nye versjonen ut på telefonene

Symptomer: «endringen slår ikke gjennom», «Importing binding name 'x' is not found»,
appen står med ny `utforsk.js` og gammel `dom.js`, sida laster på nytt og er
fortsatt gammel, sida laster på nytt mens noen skriver.

Alt her er `reiseapp/public/sw.js`, `app.js` og `oppdatering.js` (ren logikk, testet
i node), og det samme mønsteret som `vm-profeten`.

## 1. Skallet byttes som ett stykke

```js
const CACHE = 'app-v67';            // bump ved HVER endring i skallet
self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE)
    .then((c) => c.addAll(SKALL.map((u) => new Request(u, { cache: 'reload' }))))
    .then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys()
    .then((n) => Promise.all(n.filter((x) => x !== CACHE && x !== FLISER).map((x) => caches.delete(x))))
    .then(() => self.clients.claim()));
});
// fetch: skallet fra cache, og BARE fra cache. Nye filer som ikke står i lista hentes fra nett og legges inn.
```

- **Virket ikke:** stale-while-revalidate på skallet. Modulene oppdateres hver for seg,
  og en telefon sto med ny `utforsk.js` + gammel `app.js`: «Les mer» havnet på Hjem
  fordi ruta ikke fantes, Instagram-ikonet ble kjempestort fordi stilen manglet.
- **Virket ikke:** `addAll(SKALL)` uten `cache: 'reload'`. `addAll` går utenom
  fetch-handleren, men **ikke** utenom nettleserens HTTP-cache: en telefon fikk gammel
  `hjem.js` fra HTTP-cachen sammen med ny `style.css` (15. september). Sett
  `cache: 'reload'` på hver `Request`, og la serveren sende `Cache-Control: no-cache`
  på skallet.
- Nye filer må inn i `SKALL`-lista samtidig, ellers caches de ikke og appen virker
  offline helt til den skal bruke dem.
- Kartfliser i **egen cache** (`FLISER`) som overlever versjonsbytter, med et tak
  (900) og de eldste ut først.

## 2. Én versjon i minnet: importer alt tidlig, og reload ved modulfeil

Med `skipWaiting` + `clients.claim()` kan en side som står oppe under en utrulling
laste en **lat** visning fra den nye cachen oppå gammel `dom.js` i minnet:
`Importing binding name 'bildedag' is not found` (Safari) /
`does not provide an export named` (Chrome).

- Når Hjem står: `import()` **alle** visningene i ro (`requestIdleCallback`, fra
  service workerens cache, koster ingenting). Da er hele appen én versjon i minnet.
- `feil.js`: `erModulfeil(melding)` kjenner igjen importfeilene (også «Importing a
  module script failed», «failed to fetch dynamically imported module»). `vis()` laster
  sida på nytt **én gang** (vakt i `sessionStorage`) i stedet for å vise feilen.

## 3. Vit hvilken versjon som kjører

Tre tall, ikke ett:

- **skall**: versjonen bakt inn i `index.html` ved utrulling:
  `<meta name="versjon" content="$Format:%h · %cs$">` + `public/index.html export-subst`
  i `.gitattributes`. `git archive` fyller inn; i et vanlig utsjekk står `$Format`
  igjen → tolk som `null` («utviklingsversjon»).
- **server**: `GET /api/versjon` (fra `versjon.txt`, samme export-subst).
- **sw**: hvilken service worker som svarer: en syntetisk rute i SW-en
  `if (url.pathname === '/sw-versjon') respondWith(new Response(CACHE, { 'Cache-Control': 'no-store' }))`.
  Spør bare når `navigator.serviceWorker.controller` finnes (ellers 404 fra serveren
  ved første lasting). Husk svaret ved lasting (`swVedLast`).

**Virket ikke:** å sammenligne serverens versjon med *serverens versjon ved lasting*.
Reload før den nye service workeren var ferdig ga det gamle skallet en gang til med en
«ny» kjent versjon — telefonen sto der for godt. Og `hentVersjon()` var memoisert, så
sjekken så aldri noe nytt: hent med `{ fersk: true }`.

```js
export function avgjor({ skall, server, swVedLast, swNaa }) {
  if (swVedLast && swNaa && swNaa !== swVedLast) return 'last';   // SW byttet under sida (iOS gjør det uten controllerchange)
  if (skall && server && server !== skall) return 'hent';         // serveren har noe nyere enn skallet
  return 'ingen';
}
```

## 4. Når skal sida lastes på nytt (hybrid)

- **Ved forgrunn** (`visibilitychange`, `focus`): `reg.update()` + sjekk → `'hent'`
  lastes **automatisk** (ingen skriver akkurat da).
- **Under bruk** (sjekk hvert 5. minutt mens synlig): snackbar «Ny versjon av appen
  er klar» med «Hent den» — sida forsvinner ikke under fingrene.
- **Aldri mens noen har uskrevet tekst i et felt** (`skriverNoe()`: aktivt
  INPUT/TEXTAREA med innhold). Da settes `venterPaaLast`, og neste forgrunn/`controllerchange`
  tar den — i stedet for å gi opp for godt.
  **Virket ikke:** vakten definert som «et felt har fokus». Chatten har *alltid* feltet i
  fokus, så sida lastet aldri på nytt etter ni utrullinger på én natt mens telefonen lå i
  bakgrunnen. «Skriver» må bety *uskrevet tekst* i et fokusert felt.
- **Ukjent rute** (gammel `app.js` møter en lenke til en ny side): hent ny versjon og
  last på nytt én gang (`sessionStorage`-vakt) — ikke vis Hjem.
- **Virket ikke som «løsning»:** «lukk appen helt og åpne to ganger». Det var
  omgåelsen brukeren fikk i uker. Fellen lukkes i koden.
- `lastNyVersjon()`: `reg.update()` → vent på `installing|waiting` til `state ===
  'activated'` (maks 8 s) → sjekk `/sw-versjon` igjen → **først da** `location.reload()`.
  Uten service worker (første besøk) gir nettet alltid ny: reload rett.
- `controllerchange` → reload (hvis ikke skriver), men bare når det fantes en
  controller fra før (ellers er det første installasjon).
- iOS fyrer ikke alltid `controllerchange` for en app på Hjem-skjermen som kommer fra
  bakgrunnen — derfor versjonssjekken i tillegg.
- `lastNyVersjon()` svarer sant/usant (lastes / ikke noe nytt). **Virket ikke:** uten
  returverdi sto «Henter ny versjon …» for alltid når adressen bare var feil.
- Sjekken under bruk husker hvilken versjon den alt har meldt (`nyVersjonMeldt`), ellers
  kommer snackbaren hvert femte minutt for samme utrulling.
- Foten («Hent den») kan ikke importere `app.js` uten sirkulær import: den sender
  `dispatchEvent(new Event('hent-ny-versjon'))`, og `app.js` lytter.

## 5. Deploy-siden av det samme

- `git archive --format=tar HEAD | tar -x -C /srv/app/app` (ikke `git pull` på
  verten): export-subst fungerer bare gjennom `archive`.
- `systemctl restart` etterpå; `curl localhost:PORT/api/versjon` skal vise ny hash.
- Bump `CACHE` i **samme** commit som skallendringen. Glemmer du det, ser telefonene
  aldri endringen (skallet er cache-only).
- **`tar -x` pakker ut oppå og sletter aldri.** En fil som er fjernet fra repoet blir
  liggende og servert (en `inspo.js` levde lenge etter at den var borte) — slett fjernede
  filer eksplisitt, eller pakk ut i en ny mappe og bytt.
- Behold forrige versjon som `app-forrige-<sha>`: rullback er ett `mv`. Et `npm ci` som
  går i stå kvelden før avreise er ingen app i morgen tidlig — hold nye avhengigheter
  igjen til det er tid til å se dem feile.
- Native avhengigheter (`sharp` drar inn ~25 plattformspesifikke pakker) krever `npm ci`
  på verten; `git archive` alene gir en app som krasjer på import.
- **Skriftbytte er fire steder** som må følges ad: `package.json`, `server.js`
  (`/vendor/<navn>` fra `node_modules`), `index.html` (`<link>`), og `SKALL` + ny `CACHE`
  i `sw.js`. Glemmes SKALL, virker skrifta på nett og faller til systemskrift uten.

## 6. Verifiser

- `scripts/frisk-sw.mjs <basis> <cachenavn> '#/rute' …`: fersk installasjon med SW
  på, antall filer i cachen, ingen konsollfeil på de late rutene.
- `scripts/nyversjon-e2e.mjs`: appen står oppe, en «ny utrulling» skrives (versjon i
  `versjon.txt` + `index.html`, nytt cachenavn), serveren restartes, og sida skal bytte
  av seg selv ved forgrunn og vise «Hent den» under bruk. Tilpass stiene i toppen.
- `test/oppdatering.test.js`-mønsteret: `avgjor()` og `skallVersjonFra()` som rene
  funksjoner med alle fire kombinasjonene.
