# App-følelse på iPhone

Symptom: «den kjennes som en nettside». Rekkefølgen under er rekkefølgen det gir
effekt i. Alt er verifisert i `reiseapp` (vanilla PWA, iOS 26, standalone).

## Grunnmuren (gjør disse først)

1. **Standalone-modus.** `<meta name="apple-mobile-web-app-capable" content="yes">`
   + `"display": "standalone"` i manifestet. Lagt til Hjem-skjermen kjører appen uten
   Safari-krom, og **pinch-zoom er borte av seg selv**.
2. `<meta name="mobile-web-app-capable" content="yes">` ved siden av (Chrome maser
   ellers om at den apple-prefiksede er utdatert).
3. `viewport-fit=cover` i viewport-metaen, og `env(safe-area-inset-bottom)` i alt som
   ligger mot bunnen, `env(safe-area-inset-top)` på alt som ligger mot toppen (også
   Leaflets kontroller, lyskasser, «til toppen»-knapper).
4. `html, body { overscroll-behavior: none; }` — ingen gummistrikk mot kantene og
   ingen pull-to-refresh. Indre rullebokser (chat, ark) får `overscroll-behavior: contain`,
   vannrette striper `overscroll-behavior-x: contain` så de ikke drar med seg sida eller
   iOS sin tilbake-sveip.
5. `body { touch-action: manipulation; }` — dobbelttrykk er et trykk, ikke zoom.
6. `-webkit-tap-highlight-color: transparent` — og **da må du gi trykkrespons selv**:
   `@media (hover: none) { .rad:active, .knapp:active, … { background: var(--trykk); } }`.

**Virket ikke:** `user-scalable=no` og `maximum-scale=1`. iOS ignorerer dem (siden
iOS 10), de gjør ingenting på iPhone og skader andre plattformer. Standalone er svaret.

7. **Alle skrivefelt ≥ 16 px** (`input, textarea { font: inherit }` med 17 px brødtekst).
   Under 16 px zoomer Safari inn når feltet får fokus, og appen står i feil zoom resten
   av økta — den vanligste måten en PWA slutter å kjennes som en app på.
8. Skrifter **selv-hostet** (Fontsource i `node_modules`, servert under `/vendor/`) og
   lagt i service worker-skallet — ikke Google Fonts. Ingen nett = fortsatt riktig skrift.

## Tekst som følger telefonen (Dynamic Type)

```css
html { -webkit-text-size-adjust: 100%; font-size: 17px; }
/* Bare på iOS: Chrome godtar nøkkelordet, men gir 16 px uten å følge noe. */
@supports (font: -apple-system-body) and (-webkit-touch-callout: none) {
  html { font: -apple-system-body; }
}
```

Alle `font-size` i **rem**, så hele appen skalerer med rota. Da kan innstillingen
«tekststørrelse» i appen fjernes — telefonen eier den. Skrift under 13 px er
uleselig i sol; metadata på 15 px, brødtekst 17 px.

## Trykkflater og sol

- **44 × 44 px** på alt som kan trykkes (Apple sitt minstemål). Ta hele raden som
  trykkflate der det er en pil (`::after` med `position: absolute` over raden).
- Kontrast som holder i september-sol: svak tekst ikke lysere enn ~4.5:1, og
  `@media (prefers-contrast: more)` mørkner svak tekst og skillelinjer til 7:1.
- `@media (prefers-reduced-transparency: reduce)` gjør glass-flater (fanelinja med
  `backdrop-filter`) tette.
- `@media (prefers-reduced-motion)` rundt all animasjon.

## Mørk modus og oppstart

- `prefers-color-scheme` + et personlig valg i `localStorage` (mørk modus er per
  telefon, ikke delte data). **Sett temaet i et inline-script i `<head>` før første
  tegning**, ellers blinker sida lys i et mørkt rom.
- **Virket ikke:** fanelinja og kartkontrollene med hardkodet hvit bakgrunn — de forble
  lyse i mørk modus. Én `--glass`-variabel som følger temaet, og skill flatefarge
  (`--vann`) fra tekstfarge (`--vann-tekst`): aksenten trenger hver sin lys/mørk-variant.
- Mørk/lys-bryteren og tannhjulet oppe til høyre på Hjem, der folk leter.
- Lytt på `matchMedia('(prefers-color-scheme: dark)')` sin `change`: telefonen bytter
  til mørk ved solnedgang mens appen står åpen, og uten lytteren sto lys aksentpalett på
  svart bakgrunn til noen lastet på nytt. Når brukeren overstyrer temaet, følger ikke
  `theme-color`-metaene med `media=` lenger — skriv `meta[name=theme-color].content` selv.
- `theme-color` med `media="(prefers-color-scheme: …)"` i to varianter, satt til
  sidas bakgrunn (ikke aksenten) — statuslinja og Android-ramma følger den.
- Oppstartsbildet (`background_color` i manifestet) i en mørk/aksent-farge; lyst
  blendet i mørke rom.
- **Ikke** `apple-mobile-web-app-status-bar-style: black-translucent` hvis toppen av
  sidene er lys: den tvinger hvit statuslinjetekst, og klokka blir uleselig. `default`
  er trygt; hold `env(safe-area-inset-top)`-reglene klare om det snus.

## Ikoner og manifest

- iOS bruker **ikke** manifest-ikonene: `<link rel="apple-touch-icon" href="/ikon-180.png">`
  må stå i HTML. Manifestet får 192 + 512 (`purpose: any maskable`) for Android.
- `apple-mobile-web-app-title` styrer navnet under ikonet.
- **Ikonmerke** med `navigator.setAppBadge(n)`: tallet skal bety noe brukeren kan
  gjøre noe med (ugjorte punkter i dag), ikke «antall varsler». Null når dagen er tom.
  (iOS 16.4+, bare for apper på Hjem-skjermen.)
- Krever HTTPS med ekte sertifikat på iPhone; `tailscale serve --https=…` gir et
  Let's Encrypt-bevis uten offentlig eksponering.

## iOS-konvensjoner som ga app-følelse (én kveld, 17 punkter)

- Høyst **fem faner** (HIG). Det sjette innholdet får en rad under en annen fane.
- **Trykk på aktiv fane** ruller til toppen; fra en underside går det til fanens rot.
- Sticky dagoverskrifter i lange lister.
- **Bunnark** (`apneArk`) nedenfra for handlingsmenyer, i stedet for paneler som folder
  seg ut i lista. Ark låser kroppen og lukkes ved `hashchange`.
- **Sveip på rader** (venstre: slett, kort høyre: kryss av) — se navigasjon.md for
  reglene som gjør at det ikke kolliderer med iOS.
- **Deling** via `navigator.share({ title, text, files })` — bilder som `File` bare
  når `navigator.canShare({ files })` sier ja.
- **Kalender**: `webcals://` abonnement på en `.ics` (Kalender henter hvert kvarter) og
  én `.ics` per punkt; `TZID` + `VTIMEZONE`, bjella blir `VALARM`.
- Ingen `alert()`: en snackbar nederst med «Prøv igjen» (`varsle()` i `dom.js`),
  én om gangen, `role="status" aria-live="polite"`.
- Nettstripe «Uten nett — viser det vi hentet sist» på `offline`-hendelsen, og
  skrivinger som feiler på nett legges i en kø i minnet (ikke localStorage: en fane
  som var lukket i går skal ikke sende gamle endringer inn i delte data i dag).

## Det maskinen ikke kan bevise (si «antatt», ikke «målt»)

- `env(safe-area-inset-*)` er alltid 0 i headless Chrome. At layouten *tåler* Dynamic
  Island vises ved å injisere innrykk, ikke ved at Safari rapporterer dem.
- Kontrasttall regnes i sRGB; iPhone viser P3 med True Tone. Om en lenkefarge holder i
  sol, svarer bare telefonen på.
- `speechSynthesis` krever et ekte trykk på iOS og kan ikke starte selv; om lyden
  kommer ut i standalone kan ikke verifiseres fra maskinen.
- Om delingsarket tar imot bildene som filer, og om én `.ics` åpner Kalender i
  standalone: uverifisert til noen prøver på en iPhone. Abonnementslenken er den
  sikre veien.

## Lenker ut av og inn i appen (standalone)

- **Interne lenker (`#/…`) må ikke ha `target="_blank"`**: i standalone åpner `_blank`
  Safari, og man er ute av appen. Én hjelper (`utLenke`) skiller på prefiks: interne uten
  `target`, eksterne med `_blank` + `rel="noopener"`.
- Rett inn i native apper: `https://maps.apple.com/?daddr=LAT,LNG` (Apple Maps i
  navigering), `https://www.google.com/maps/search/?api=1&query=LAT,LNG`; `tel:` og
  `mailto:` som knapper med mellomrom strippet (`telefon.replace(/\s+/g, '')`). Det er
  slike knapper som gjør en side til en app.
- Nettadresser i fritekst blir trykkbare med en regex som ikke tar med avsluttende
  tegnsetting (`https?:\/\/[^\s<>()«»]+[^\s<>()«».,;:!?]`) og vises uten `https://www.`.
- **`title`-attributter når aldri en iPhone** (ingen hover). Forklaringer i DOM-en.
- **Installasjonshint** bare når `!navigator.standalone`, avvist per telefon i
  `localStorage` — aldri mas etter ett «skjul».

## Opplesing (`speechSynthesis`)

Stemmelista er tom ved første `getVoices()`: kall én gang *og* lytt på `voiceschanged`.
`cancel()` før hvert `speak()` (ellers køer iOS opp alt som er trykket), `rate ≈ 0.85` så
det går an å si etter, `lang = 'it-IT'` som reserve når ingen italiensk stemme finnes.
Uten `'speechSynthesis' in window` er raden en `div`, ikke en knapp, og uttalen står
skrevet. Krever et ekte trykk på iOS.
