# Design som holder på en telefon i sol (PWA-spesifikt)

Kort. Resten av designsystemet hører til prosjektet (`docs/design.md`, DESIGN.md);
dette er det som gjentar seg fra app til app.

- **Én skjerm, én ting.** Hjem svarer på «hva skjer i dag» uten å rulle. Én
  «i dag»-boks, ikke i dag + i morgen + notater + sider. Fjern det som er tilgjengelig
  ett trykk unna likevel.
- **Få bokser, og hver boks skal bety noe.** Bakgrunn tydelig mørkere enn boksene
  (stein `#e6e9e5` mot hvit), 1 px hårfin kant på alle bokser, ingen bokser inni bokser.
- **Ett aksentbudsjett.** Aksenten (tomat) bare på det som gjelder *nå*: høyst fire
  merker per skjerm. Alt annet i blekk/svak.
- **Lister på 30 000 px er ubrukelige.** Kompakte rader (64 px bilde, navn, kategori,
  brikke), søk og filtre som brytes til to rader (ikke en stripe som går utenfor
  skjermen), sammenleggbare grupper. Utforsk: 36 509 → 2 245 px.
- **Tomtilstander som sier noe** («Ingenting her ennå», «Det første kommer nok fra
  båten») og lastetilstander bare der det faktisk ventes.
- **Emoji som ikoner** ser ulike ut på iPhone/Android/Mac og mangler på noen
  (tomt rektangel i headless Chrome). Tegn små inline-SVG-er (24 px, 1,8 px strek) via
  én `svg(bane)`-hjelper.
- **Handlingsknapper ut av rader.** Lenke/rediger/slett samlet i én `···`-meny (bunnark)
  så teksten får bredden; slett aldri som den mest synlige knappen. Sveip som snarvei.
- **Programpunkter med klokkeslett** sorteres innen dagen; «forslag:» tegnes som forslag
  (stiplet), ikke som avtaler.
- **Tilbakemelding**: snackbar, ikke `alert()`; `:active`-flate på alt som kan trykkes;
  «sist hentet kl.» der data kan være gamle.
- **Skrift**: én titteltype i én vekt (størrelsen bærer hierarkiet) + én variabel
  brødtekst, selv-hostet fra `node_modules` under `/vendor/`. Boka (print) tåler mer
  enn appen — en art déco-forside i boka, ikke i appen.
- **Kart**: Leaflet med gratis fliser uten nøkkel (OSM, OpenTopo, Esri) og fliser i SW.
  Google Maps krever betalingskort selv for gratiskvoten; CARTO stempler «API KEY
  REQUIRED» på flisene. «Min posisjon»-knapp og tegnforklaring er det kartet brukes til.
- **Mål før/etter** med et skript som teller trykkflater < 44 px og skrift < 13 px;
  kravet er null.
- **Kontrast målt, ikke beskrevet:** AA-brudd 13 → 2, lenketekst 3,94 → 5,77, feltkanter
  1,25 → 3,58, fokusring 1,68 → 8,98.
- **Ingresser under overskriftene ut** (16 stykker): de koster en linje øverst på hver
  side og er lest etter tre dager. Unntak: tekst som er innhold.
- **Asynkrone data inn i plassholdere**, ikke ny tegning av sida: `replaceChildren` i en
  `span.vaer-plass` når været lander. Å tegne Hjem på nytt kastet rulleposisjon og blafret.
- **Innhold som skal være likt på to telefoner velges av datoen**, ikke `Math.random`
  («dagens frase» = `floor(Date.now()/86_400_000) % n`).
- **Sammenleggbare grupper** som `<details>/<summary>` med `ontoggle` → `localStorage`;
  tastatur og skjermleser gratis. **Søk uten aksenter** (`normalize('NFD')` + strip
  kombinerende tegn) på begge sider. **Forhåndsvisninger** stripper markdown, ellers står
  `**sen dag**` på forsiden. **Rekkefølge** med opp/ned-knapper, ikke dra-og-slipp.
- **Optimistisk UI** med angre: `proev(handling, { feiltekst, angre })` snur haken straks
  og tilbake når skrivingen feiler; snackbar med «Prøv igjen». Bekreft en skriving og tøm
  feltet. `varighet: Infinity` for meldinger som skal bli stående — men
  `setTimeout(…, Infinity)` fyrer straks, så vakt med `Number.isFinite`.
- **Avgjørende fakta øverst** (avstand, varighet, pris) som brikker; adresse og
  åpningstid i en `<dl>` under teksten. Kort i lista = bilde, navn, avstand, første setning
  (`^.{20,}?[.!?](\s|$)`), én faktalinje; alt annet på egen side.
- **Virket ikke:** et helt kort som `<a>` når punktene inne i det fikk egne lenker — lenke
  i lenke. Kortet er `<div>` med en lenke øverst og en nederst. `<option>`-tekst kuttes på
  390 px: kort ukedag og dato. Enheten på en brikkerad («m/s») henges på siste brikke, så
  den ikke brekker alene. Klokkeslett med `<input type="time">` (iOS-hjulet), lagret som
  `HH.MM`, normalisert på serveren («8.55», «08:55», «0855»).
- **Aksent som hel palett** (`--vann`, `--vann-lys`, `--vann-lenke`, `--vann-blek`), ikke én
  verdi — **Virket ikke:** bare bytte `--vann`; lenker og flater passet ikke sammen.
- **SPA uten avmontering**: intervaller rydder seg selv
  (`kort.isConnected ? tegn() : clearInterval(takt)`) — og refererer et element som alt
  finnes (TDZ ellers).
- **Sjekklister fra designverktøy** (impeccables «side-tab = AI-UI») er verdt å kjøre,
  men funnene må måles fram: de fargede venstrekantene var et *dokumentert*
  aksentsystem, og ble beholdt til de faktisk ble målt som støy.
