# Service worker: hva som caches, og hva som må slippes forbi

Symptomer: «Returned response is null» i Safari, strømmede svar kommer på én gang,
PDF-en åpner ikke, cachen er full, data er gamle uten at man ser det.

Hele fila: `reiseapp/public/sw.js` (~110 linjer). Versjonsbyttet står i
oppdatering.md; dette er fetch-strategiene.

## Tre klasser av forespørsler

| Hva | Strategi | Hvorfor |
| --- | --- | --- |
| App-skallet (HTML, CSS, JS, vendor, ikoner, manifest) | cache, **bare** cache | byttes som ett stykke ved versjonsbytte; se oppdatering.md |
| `/api/`, `/vedlegg/`, `/album/` | nett først, cache som fallback, **503 JSON** hvis ingen av delene | sist viste data, åpnede PDF-er og sette bilder finnes uten nett |
| Kartfliser (`tile.openstreetmap.org` m.fl.) | cache først, egen cache med tak | på et relé i Italia er det forskjellen på et kart og et grått felt |

Alt annet (andre opphav) rører SW-en ikke (`if (url.origin !== location.origin) return`).
Bare `GET`.

**En SPA svarer alle navigeringer med skallet.** Hver adresse i appen er samme side, så
oppslaget i cachen gjøres på `/`, ikke på adressen:
`caches.match(req.mode === 'navigate' ? '/' : req)`. Ellers virker `#/`-ruter offline,
men en dyp lenke til `/liste/3` gjør det ikke.

## Det som MÅ gå utenom (`return` uten `respondWith`)

- **Hendelsesstrømmer (SSE)**: `if (url.pathname.includes('/samtaler/')) return;`
  Å klone en uendelig strøm for `cache.put()` lar nettleseren (Safari) buffre hele
  svaret og levere det på én gang i stedet for bit for bit. Rett til nettet.
- **Store filer** (PDF-en av fotoboka, 20 MB, og sidebildene):
  `if (url.pathname.endsWith('.pdf') || url.pathname.includes('/fotobok/')) return;`
  Å legge den i cachen feilet på iPhone, og da svarte handleren med ingenting:
  **«FetchEvent.respondWith … Returned response is null»**. Regelen: en fetch-handler
  må alltid ende i et `Response`-objekt eller ikke svare i det hele tatt.

## Størrelsesvakt og fallback

```js
function leggICache(req, svar) {
  if (!svar.ok) return;
  const lengde = Number(svar.headers.get('content-length') || 0);
  if (lengde > 4 * 1024 * 1024) return;          // aldri noe stort: put() kan feile og fylle cachen
  caches.open(CACHE).then((c) => c.put(req, svar)).catch(() => {});
}
// nett-først:
fetch(req).then((s) => { leggICache(req, s.clone()); return s; })
  .catch(() => caches.match(req).then((c) => c || new Response(JSON.stringify({ feil: 'Uten nett, og ingenting lagret fra før' }), { status: 503, headers: { 'Content-Type': 'application/json' } })));
```

Appen kan da behandle 503 som «uten nett» i stedet for å krasje på `null`.

**Merk svaret som kom fra lageret.** Uten nett og med en kopi gir nett-først et svar
som ser ferskt ut. Sett en header på kopien, så sida kan si «tallene er fra i går»:

```js
function fraLager(svar) {
  const headers = new Headers(svar.headers);
  headers.set('x-fra-lager', '1');
  return new Response(svar.body, { status: svar.status, statusText: svar.statusText, headers });
}
// .catch(() => caches.match(req).then((c) => (c ? fraLager(c) : UTEN_NETT())))
```

**API-et får `no-store` som standard.** Service workeren eier strategien for `/api/`;
en HTTP-cache som også har en mening, gir en gammel oversikt som er verre enn ingen.
En mellomvare som setter `Cache-Control: no-store` på alle `/api/*`-svar som ikke har
satt noe selv.

## Flisecachen

Egen cache (`app-fliser-v1`) som ikke slettes ved versjonsbytte. Bare fliser som
faktisk er sett (ingen bulknedlasting — flisekildenes vilkår). Tak på 900; når det er
nådd, slettes de eldste (`c.keys()` er i innsettingsrekkefølge) — med en `rydder`-lås
så to samtidige fetch ikke rydder oppå hverandre. Uten tak vokste den til telefonen sa
nei.

 Flisesjekken på vertsnavn må stå
*før* `if (url.origin !== location.origin) return`, og være forankret
(`/(^|\.)(tile\.openstreetmap\.org|…)$/`) — en delstrengsjekk hadde matchet
`tile.openstreetmap.org.angriper.no`. **Virket ikke:** `slice(0, antall − tak)` som
rydding: negativ sluttindeks når taket ikke er nådd, og de *første* flisene slettes i en
halvfull cache — `if (antall <= tak) return` først. Og `crossOrigin: true` handler også om
kvote: ugjennomsiktige svar polstres av nettleseren og teller flere MB *hver*.
**Virket ikke først:** flisene ble aldri cachet. Leaflet hentet dem uten CORS, svarene
var *opaque* (`svar.ok === false`), og SW-en kunne ikke se om de gikk bra. `crossOrigin:
true` på flislagene. Og CARTO svarer 200 med «API KEY REQUIRED» stemplet på bildet — se
på flisene, ikke statuskoden. Verifisert med nettet fysisk kuttet.

## Kald start og «sist hentet»

- Turen (68 KB JSON) tegnes fra **siste kopi i `localStorage`** med en gang, og hentes
  på nytt i bakgrunnen; er den ferske annerledes, tegnes visningen på nytt — men ikke
  mens noen skriver i et felt, og ikke på chatsida (tråden lever på strømmen).
- `sistHentet` vises på Hjem, så «hvorfor står det ikke her ennå» har et svar.
- Nettstripa som lyttet på `DOMContentLoaded` kom aldri — hendelsen hadde alt vært.
  Kall den umiddelbart ved lasting og på `offline`/`online`.
- Én bakgrunnsoppfrisking om gangen — hver `vis()` (hashchange, forgrunn) ville ellers
  stable 68 KB-hentinger på dårlig nett. **Men ikke bare `oppfrisking ??= …`:** en
  skriving rett etter at en henting har startet, får da svaret fra *før* skrivingen.
  Kommer et kall mens en henting pågår, hent én gang til etterpå, og gi kalleren
  *den* hentingen. Da får kalleren det ferske svaret, og en feil når fram til den som
  venter, i stedet for å bli en uhåndtert rejection i en henting ingen eier:

  ```js
  let paagaar = null, neste = null;
  export function hent() {
    if (!paagaar) return (paagaar = hentFersk().finally(() => { paagaar = null; }));
    // Alle som kommer mens en henting pågår, deler én ny henting etterpå.
    neste ??= paagaar.catch(() => {}).then(() => { neste = null; return hent(); });
    return neste;
  }
  ```
- Memoisert henting på modulnivå («én gang per sidevisning») trenger en eksplisitt
  `glem()` etter en skriving, og en feilet henting må nullstille seg selv.
- Nettfeil vs. serverfeil: `fetch` uten svar kaster `TypeError` → kø og prøv igjen ved
  `online`; en 400 fra serveren skal aldri prøves igjen.
- Genererte bilder med *stabil* URL (sidebildene av boka) får byggetidspunktet i spørringen
  (`?v=${bygd}`), ellers viser `<img>` forrige bygg fra HTTP-cachen selv om SW-en slipper
  stien forbi.
- Server-side cacher trenger et **formatversjonsnummer** (`VAER_VERSJON`): en `vaer.json`
  fra før vindfeltet fantes levde i tre timer etter utrulling, og vinden var tom i prod.
- CDP: `Network.emulateNetworkConditions({ offline: true })` flipper ikke
  `navigator.onLine` ved kald last — stub den via `Page.addScriptToEvaluateOnNewDocument`.
- **Forgrunn = hent på nytt.** Ingen websockets: den andre telefonen kan ha endret
  noe imens, og `visibilitychange` → `vis({ fersk: true })` dekker det.
- `<link rel="modulepreload">` på det Hjem trenger: ellers henter nettleseren modulene
  ett ledd om gangen, og hvert ledd er en tur-retur.

## Serveren

- `compression()` på alt **unntatt** SSE-ruta (`filter: (req) => !req.path.includes('/samtaler/')`)
  — gzip bufrer strømmen.
- Skallet: `Cache-Control: no-cache` (SW-en eier cachen, HTTP-cachen skal ikke ha en
  mening). Vendor og småbilder: `public, max-age=7d, immutable`. Dynamiske PNG/SVG:
  `no-cache` eller kort `max-age`. Ulik levetid per mappe: album/bilder med
  tilfeldige id-navn `7d immutable`, vedlegg som kan byttes under samme navn `1d`,
  småbilder 30 dager.
- PDF som skal *åpnes* på iPhone: `Content-Disposition: inline; filename="…"` +
  `type('application/pdf')` + `no-cache`, ellers laster Safari ned i stedet for å vise.
- SSE: `Content-Type: text/event-stream`, `Cache-Control: no-cache, no-transform`,
  `X-Accel-Buffering: no`, et `: puls` hvert 25. sekund så mellomledd ikke tror
  forbindelsen er død. `EventSource` kobler seg på igjen selv; første hendelse skal
  være **hele tilstanden**, så gjenoppkobling er gratis.
- Egen `express.json({ limit: '24mb' })` på ruta som tar imot bilder — den globale
  grensa ga 413 før ruta så forespørselen.
- Småbilder (640 px JPEG) lages av serveren første gang de bes om og legges i
  `<data>/mini/`; kort og rutenett bruker dem, lyskassa originalen. 21 MB → 0,6 MB per
  runde.
