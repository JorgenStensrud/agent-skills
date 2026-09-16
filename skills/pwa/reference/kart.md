# Kart i en PWA (Leaflet, fliser, posisjon, egne SVG-kart)

- **Leaflet, ikke Google Maps.** Google krever betalingskort på en Cloud-konto selv for
  gratiskvoten, hver visning brenner av den, og uten nøkkel får man en iframe med én pinne.
  Gratis fliser uten nøkkel: OSM, OpenTopo, Esri. **CARTO** svarer 200 med «API KEY
  REQUIRED» stemplet på flisa — se på flisene, ikke statuskoden.
- **Last Leaflet lat** når kartet åpnes (150 KB spart per side): `<link>` + `<script>` i
  `<head>` med `onload/onerror`, memoisert i ett promise som nullstilles ved feil,
  plassholder «Henter kartet …». `L.map(boks)` trenger en boks med størrelse — tegn i
  `requestAnimationFrame` etter at visningen står i DOM-en. Filene står likevel i
  SW-`SKALL`, så kartet virker uten nett.
- **Fliser offline**: egen cache i SW-en med tak, `crossOrigin: true` på flislagene (ellers
  opaque svar som verken kan sjekkes eller caches billig) — se service-worker.md.
- **Klynger** (`leaflet.markercluster` fra `node_modules` under `/vendor/`, JS + CSS i
  SKALL, lastet etter Leaflet med vakten `window.L?.MarkerClusterGroup`):
  `maxClusterRadius: 45`, `divIcon` på 44 px. 77 pinner uten klynger = halve gamlebyen én
  prikk man ikke kommer inn i. Dagens punkter som nummererte `divIcon` med
  `zIndexOffset: 1000` utenfor klyngene.
- **Lagvalg** (kart/satellitt/terreng) i `localStorage`; tegnforklaring nederst; Leaflets
  kontroller under `env(safe-area-inset-top)`; attribusjonen unntas fra trykkflate-måling
  (10 px er lisenskrav).
- **Posisjonsknapp**: `getCurrentPosition` bare ved trykk,
  `{ enableHighAccuracy: true, timeout: 10000, maximumAge: 30000 }`; `code === 1` → «Slå
  på stedstjenester for Safari» (standalone arver Safaris tillatelse); nøyaktighet som
  sirkel `L.circle(punkt, { radius: max(accuracy, 25) })`.
- **Lenker rett inn i Apple/Google Maps** fra hver pinne og hvert sted (app-folelse.md).
- **Egne kart som SVG fra ekte geometri** (til bok og app): strandlinje/sti fra OSM
  (Overpass, bruk et speil ved rate limiting), kjørerute fra OSRM, landomriss og innsjøer
  fra Nominatim (`polygon_geojson=1&polygon_threshold=…`, egen `User-Agent`), lagret som
  forenklede ringer i seed. Rene funksjoner gir SVG-tekst: flat projeksjon med `cos(lat0)`,
  `toFixed(1)`, deterministisk LCG for bølger, stråle-test for «i sjøen», ikoner som små
  `<g>`-grupper (båt, fjell, sykkel, fly, Duomo, Arena, det skjeve tårnet). Serveres som
  `image/svg+xml` med kort `max-age`, vises i `<img>`/lyskasse, brukes rett i PDF-en.
  **Virket ikke:** en grov landegrense (`polygon_threshold=0.03`) som stiplet linje —
  rotete; fjernet. Test: `!svg.includes('NaN')` og at navnene finnes.
