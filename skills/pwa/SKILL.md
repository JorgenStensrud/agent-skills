---
name: pwa
description: >-
  Bygge, feilsøke eller polere en installerbar web-app (PWA) for iPhone: «kjennes som
  en nettside», fanelinje og tastatur, service worker og caching, oppdatering som ikke
  når telefonen, chat med strømmede svar, push-varsler, testing i headless Chrome,
  deploy og drift. Bruk også før du sier «ferdig» på en PWA-endring.
---

# PWA på iPhone

Erfaring fra to apper: `reiseapp` (Express 5 + vanilla ES-moduler, service worker,
push, chat med SSE, agent på serveren, PDF-bok, to telefoner på delte data), destillert
fra 107 utviklingsøkter 10.–16. september 2026, og en React/Vite-app med byggesteg,
push og agent, pluss `polykompis`/`vm-profeten`. Alt er
prøvd på ekte iPhoner i standalone-modus; det som står som «Virket ikke» ble prøvd og
forkastet — ikke gjenta det.

## Slå opp etter symptom

| Symptom | Les |
| --- | --- |
| «Kjennes som en nettside», zoom (også ved fokus i felt), gummistrikk, ting under hjemindikatoren, tekst som ikke følger telefonen, ikoner, mørk modus som blinker | [reference/app-folelse.md](reference/app-folelse.md) |
| Fanelinja forsvinner/står midt på skjermen, feltet under tastaturet, tilbake havner på toppen, chatten kan ikke rulles, sveip krangler med iOS, bunnark/lyskasse | [reference/navigasjon.md](reference/navigasjon.md) |
| Endringen når ikke telefonen, `Importing binding name … is not found`, reload gir gammel versjon, reload aldri/midt i skriving, gamle filer serveres etter deploy | [reference/oppdatering.md](reference/oppdatering.md) |
| «Returned response is null», strøm kommer på én gang, PDF åpner ikke, cachen full, fliser caches ikke, gamle data uten at man ser det | [reference/service-worker.md](reference/service-worker.md) |
| Tråden rykker til bunns, svar «fryser», `**stjerner**` i svaret, «null» i DOM-en, harde kanter, bilder i svar, kommandoer | [reference/chat-og-stromming.md](reference/chat-og-stromming.md) |
| Push-tillatelsen forsvinner, varsler blir liggende, dobbelt, midt på natta, dødt abonnement, endepunkt som SSRF-flate | [reference/push-varsler.md](reference/push-varsler.md) |
| Skal verifisere uten telefon: skjermbilder, fersk SW-installasjon, konsollsveip, E2E på oppdatering, måling før/etter, falske grønne | [reference/testing.md](reference/testing.md) + `scripts/` |
| Deploy, versjon, rullback, HTTPS uten offentlig adresse, systemd, ytelse på dårlig nett, delte data, sikkerhetskopi | [reference/drift.md](reference/drift.md) |
| Design som holder i sol: få bokser, lister som ikke er 30 000 px, kontrast målt, ikoner, tomtilstander | [reference/design.md](reference/design.md) |
| Kart: Leaflet lat, fliser offline, klynger, posisjonsknapp, egne SVG-kart fra ekte geometri | [reference/kart.md](reference/kart.md) |
| En agent i appen: Pi-sesjon på serveren, Max-innlogging som «ser ut som Claude Code», skrivepolitikk, kontekst-trimming, verktøy som alltid er «usikre», nettlesing | skillen `agent-i-appen` (`skills/agent-i-appen/`) |

## De tolv reglene som kostet mest å lære

1. **Standalone er mekanismen.** `apple-mobile-web-app-capable` + `display: standalone`
   fjerner Safari-krom og pinch-zoom. `user-scalable=no` gjør ingenting på iOS. Og alle
   skrivefelt ≥ 16 px, ellers zoomer Safari ved fokus.
2. **Skallet byttes som ett stykke.** Cache-only på skallet, nytt `CACHE`-navn ved hver
   endring, `addAll` med `cache: 'reload'` (HTTP-cachen lurer deg ellers),
   `skipWaiting` + `clients.claim()`. Stale-while-revalidate på ES-moduler gir to
   versjoner i samme side. Med byggesteg er cachenavnet en hash av byggefilene, skrevet
   inn av bygget (`scripts/skall-til-sw.mjs`), ikke bumpet for hånd.
3. **Importer alle visninger i ro etter første tegning**, og reload én gang ved
   modulfeil (`erModulfeil`) eller ukjent rute. Lat lasting + utrulling midt i økta =
   importfeil. Gjelder visninger lastet som egne moduler uten bundler; med bundler,
   legg visningene i hovedbunten og lat-last bare det tunge og sjeldne.
4. **Tre versjonstall**: skallet (bakt inn via `export-subst` i `index.html`, eller via
   `define` fra `versjon.txt` med byggesteg), serveren (`/api/versjon`),
   service workeren (`/sw-versjon`). Reload **først når den nye SW-en er aktivert**,
   aldri mens noen har *uskrevet tekst* (ikke bare fokus) i et felt; auto ved forgrunn,
   «Hent den» under bruk, sjekk hvert 5. minutt.
5. **Tastaturet**: `position: fixed` måles mot layout-viewporten; bruk en målestokk
   (største visuelle høyde uten tastatur) fra `visualViewport`, ikke
   `innerHeight − vv.height − offsetTop`. Gjem fanelinja, la panelet følge
   `--vv-top`/`--vv-hoyde`. Ikke tastatur uten fokus i et felt, ikke ved knip-zoom,
   nullstill ved rotasjon.
6. **Ingen gest må `preventDefault` på det som ruller.** Dra-ned-for-å-hente startes
   bare utenfor rullende forfedre; de første 24 px fra venstre kant er iOS sin gest.
7. **SW-en må slippe forbi** SSE-strømmer, PDF-er og alt over 4 MB — og en
   fetch-handler må aldri ende i `null`. Nett-først med 503-JSON som siste fallback.
   Fliser trenger `crossOrigin: true` for å kunne caches.
8. **Følg bunnen bare når brukeren står der** (`naerBunn`, 80 px), med «↓ Nytt
   nederst». `append` biter, aldri `textContent = alt`. Aldri `innerHTML` på
   modelltekst; formatér når svaret er ferdig. Serveren eier samtalen.
9. **Push på iOS**: alltid `showNotification` (ellers trekkes tillatelsen), `tag` per
   sak *og* lukk gamle med samme tag først (iOS erstatter ikke selv), lukk varslene når
   appen kommer i forgrunnen, stille timer i brukernes tidssone,
   hvert varsel én gang (logg på disk), tak per døgn, bare ekte push-verter (hvitliste
   på vertsnavn), verten må aldri sove.
10. **Rulleminne som iOS**: tilbake lander der du var, videre starter på toppen; trykk på
    aktiv fane ruller til toppen. Høyst fem faner.
11. **Verifiser som en telefon ville sett det**: headless Chrome med
    `setDeviceMetricsOverride(390, mobile)` *etter* lasting, `setBypassServiceWorker`,
    `about:blank` mellom hash-navigeringer, ekte `dispatchTouchEvent` — og **les**
    skjermbildet. Chrome utvider layout-viewporten ved horisontal overflyt; iOS gjør
    ikke det. Si «målt» eller «antatt».
12. **Deploy er `git archive` + restart + `curl /api/versjon` + fersk SW-sjekk.** `tar -x`
    sletter aldri; behold forrige versjon for rullback; `localhost` på verten er
    produksjon.

## Arbeidsmåte

- Rene funksjoner for alt som kan være det (tastaturmål, rulleminne, sveip,
  versjonsavgjørelse, utløsere, markdown), testet i `node --test`. Nettleseren bare
  for det som må.
- Mål før og etter (sidehøyde, trykkflater < 44 px, skrift < 13 px, MB per runde på
  strupet nett) og skriv tallene inn i planen.
- Uten byggesteg: bump SW-cachen i samme commit som skallendringen. Med byggesteg:
  la bygget sette den (regel 2), for å bumpe for hånd blir glemt.
- Ved feilsøking: sjekk hvilken **versjon** telefonen kjører før noe annet
  (`/api/versjon` vs. foten i appen vs. `caches.keys()`).
- Når noe ikke kan bevises fra maskinen (safe-area, tastatur, P3, push-vekking): si det,
  og be om et skjermbilde fra telefonen i stedet for å gjette videre.

## Skriptene

`scripts/skjerm.mjs`, `skjerm-fake-strom.mjs`, `frisk-sw.mjs`, `konsoll.mjs`,
`ios-sjekk.mjs`, `nyversjon-e2e.mjs` — se tabellen i reference/testing.md. De to
siste har ruter, velgere og miljøvariabler fra én app; kopier og juster. Alle finner
Chrome via `chrome.mjs` (`CHROME` overstyrer). `skall-til-sw.mjs` hører til bygget
(oppdatering.md avsnitt 6).

## Vedlikehold

Ny lærdom fra en PWA-økt hører hjemme i den referansefila symptomet peker på, som ett
punkt med HVA og HVORFOR, og «Virket ikke:» der noe ble forkastet. Legg nye
verifiseringsskript i `scripts/` i generalisert form (basis-URL som argument).
