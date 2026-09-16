# Navigasjon, fanelinje og tastatur

Symptomer: fanelinja forsvinner eller står midt på skjermen; chatfeltet er under
tastaturet; man havner på toppen av lista hver gang man går tilbake; sveip på en rad
utløser iOS sin tilbake-gest.

## Fanelinja skal ikke flytte seg

`position: fixed; bottom: 0` med `padding-bottom: env(safe-area-inset-bottom)` og
`body { padding-bottom: calc(var(--faner-h) + env(safe-area-inset-bottom)) }`. Glass
med `backdrop-filter: blur(14px)` (tett i `prefers-reduced-transparency`).

**Fellen:** på iOS i standalone måles `position: fixed` mot **layout**-viewporten.
Når tastaturet kommer opp, gjør iOS én av to ting, avhengig av versjon og situasjon:

1. Layout-viewporten står; den **visuelle** krymper og *flyttes ned* så feltet blir
   synlig. `visualViewport.offsetTop` = tastaturhøyden. Alt som er `fixed` er rullet ut
   av bildet i toppen — fanelinja sto rett over tastaturet, overskriften var borte.
2. Layout-viewporten krymper (`innerHeight` blir mindre). `offsetTop` = 0.

**Virket ikke:** `innerHeight − vv.height − vv.offsetTop` som tastaturhøyde — gir 0 i
begge tilfellene. Det som holder er en **målestokk**: største visuelle høyde sett uten
tastatur; alt som mangler fra den er tastatur (`public/tastatur.js`, ren funksjon,
testet i node):

```js
export function maalTastatur({ hoyde, offsetTop, maks, skala = 1, skriver = true }) {
  const zoomet = Math.abs(skala - 1) > 0.01;
  const nyMaks = zoomet ? maks : Math.max(maks, hoyde + offsetTop);
  const dekket = Math.round(nyMaks - hoyde);
  const tastatur = skriver && !zoomet && dekket > 60 ? dekket : 0;
  return { tastatur, maks: nyMaks, top: Math.round(offsetTop), synligHoyde: Math.round(hoyde) };
}
```

To vakter som ellers fikk fanelinja til å forsvinne av og til:
- **Knip-zoom** krymper den visuelle viewporten og flytter `offsetTop`; da verken
  læres målestokk eller meldes tastatur (`skala ≠ 1`).
- **Ingen som skriver** (`document.activeElement` er ikke INPUT/TEXTAREA) → ikke
  tastatur, uansett hva som mangler (rotasjon, verktøylinje).

Bindingen (`folgTastatur` i `spor.js`): lytt på `visualViewport` `resize` **og**
`scroll`, sett `--vv-top`, `--vv-hoyde`, `--tastatur` på `<html>` og klassen
`tastatur-oppe`. Nullstill målestokken ved rotasjon (`screen.orientation` `change`,
med 300 ms forsinkelse), mål på nytt 50 ms etter `focusout` (iOS sender ikke alltid
`resize` når tastaturet går ned etter et lenketrykk) og ved `hashchange` bort fra sida.

```css
.tastatur-oppe .faner { display: none; }   /* borte er bedre enn midt på skjermen */
.tastatur-oppe body { padding-bottom: 0; }
.tastatur-oppe .spor-side { top: var(--vv-top, 0px); height: var(--vv-hoyde, auto); bottom: auto; padding-top: 0; }
```

Regelen er global: den gjelder også pakkelista og andre sider med felt — fanelinja har
ingen jobb bak et tastatur. Kjent forbehold: terskelen på 60 px kan la et flytende eller
delt iPad-tastatur slippe under.

Rull tråden til bunns **bare når tastaturhøyden faktisk endrer seg** — `scroll`-
hendelsene kommer også når brukeren drar.
**Valg i en liste over skrivefeltet** (kommandolista) på `pointerdown` + `preventDefault`,
ikke `click`: et klikk tar fokus fra feltet og lukker tastaturet før valget er gjort.
**Søkefelt som tegner visningen på nytt per tastetrykk**: flytt fokus tilbake i
`requestAnimationFrame` og `setSelectionRange(len, len)`, ellers mister feltet fokus og
tastaturet lukker seg etter én bokstav. Søketekst og filter som modulvariabler som
nullstilles på `hashchange` — forgrunn/oppfrisking tegner på nytt uten å nullstille.

## Et fast panel der bare lista ruller (chat)

Panelet er `position: fixed; top: 0; bottom: calc(var(--faner-h) + safe-area)` som
flex-kolonne: overskrift, `.samtale { flex: 1; min-height: 0; overflow-y: auto;
overscroll-behavior: contain }`, status, skrivefelt. Da står feltet stille uansett hva
som kommer inn, og siden bak ruller ikke.

**Virket ikke:** vanlig side med skrivefelt nederst. Tastaturet skjøv alt, og
pull-to-refresh tok fingeren når man prøvde å rulle tråden («Refresh refresh»).

**Virket ikke:** sticky skrivefelt over en side som ruller — feltet fulgte med for hver
tekstbit, og «bunnen av dokumentet» lå bak tastaturet. Målt etterpå: feltet på nøyaktig
samme piksel før og etter 2 925 px strømmet svar.

## Dra-ned-for-å-hente må ikke kapre berøringen

Gesten kalte `preventDefault` etter 12 px nedover — nøyaktig det som stopper native
rulling. På et fast panel står *vinduet* alltid på toppen, så hvert drag i chatten (og
kartet) ble tolket som «hent på nytt»: **chatten kunne ikke rulles.** Regel: gesten
starter bare når fingeren ikke lander i noe som ruller selv (en forfader med `overflow`
og mer innhold enn plass, eller Leaflet), og avbrytes når draget er mer sideveis enn
nedover. Målt med ekte berøring i headless: gammel versjon avbrøt 12 av 12
fingerbevegelser, ny 0 av 11.
Detaljer: `touchmove` med `{ passive: false }` (ellers virker ikke `preventDefault`),
arm bare når `window.scrollY <= 0` og `e.touches.length === 1`.

## Rulleminne som iOS

Går du *tilbake*, kommer du dit du var; går du *videre*, starter du på toppen.
`lagRulleminne()` i `public/rull.js`: en stakk av stier, posisjon per sti; en
navigering til en sti som alt står i stakken er et «tilbake» (også nettleserens
tilbake, pila på sida, et fanetrykk), og alt over den glemmes. Kalles idet adressen
endrer seg, mens den gamle sida fortsatt står (`scrollY` leses da).

**Virket ikke:** `scrollTo(0, 0)` på hver adresseendring — toppen av en 36 000 px
liste hver gang man kom tilbake fra et sted.

Tilbake-lenken på undersider går **dit du kom fra** (`history.back()` når appen selv
har en forrige side), ellers til foreldresida.

- Rulleminnet eksponerer `varTilbake`, og visninger som ruller seg selv fram (Program →
  dagen i dag) **lar være når siste navigering var et tilbake**. **Virket ikke:** Program
  hoppet til i dag også når man kom tilbake fra et sted, og overkjørte rulleminnet.
- Data som kommer etterpå (været) gjør lista høyere: rull til dagen igjen *bare* hvis ingen
  har rullet siden — mål `scrollY` i dobbel `requestAnimationFrame` etter første tegning
  og sammenlign (< 2 px) før `scrollIntoView`.
- En dyplenke (fra programpunkt eller kart-popup) må vinne over et lagret listefilter:
  velg filteret så målet er synlig, og `scrollIntoView({ block: 'center' })`. Ellers
  lander man i en liste der målet er filtrert bort, og lenken ser død ut.
- Startfane fra innstillinger bare når appen åpnes **uten hash**, én gang per lasting, med
  `location.replace(...)` — ikke `location.hash =` (ekstra historikkpost, og hver visning
  hoppet tilbake til startfanen).
- `vis()` forkaster tegningen hvis hash har endret seg mens visningen ble hentet (lat
  import, bakgrunnshenting); ellers tegnes forrige side oppå den nye ved to raske trykk.
- En rute kan lyse opp en annen fane enn sin egen (`[regex, visning, fane]` i
  rutetabellen): kartet ble en lenke inne i Utforsk da Kart-fanen ble til Spør.

Fem faner, ikke seks: med seks ble etikettene 11 px og fanene 65 px brede, og man
traff feil; fem gir 78 px. Fanelinja er `grid: repeat(n, 1fr)` der JS setter n, så
rekkefølgen kan stokkes i innstillinger. Lange lister får `position: sticky`
seksjonsoverskrifter (dagene i programmet).

**Ukjent rute skal ikke vise Hjem.** Etter en utrulling kan gammel `app.js` få lenker
til nye sider; da hentes ny versjon og sida lastes på nytt én gang (sessionStorage-vakt,
aldri løkke) — se oppdatering.md.

## Fanetrykk

`fanetrykk(aktivFane, sti, fane)` → `'bytt' | 'topp' | 'rot'`. På `'topp'`:
`preventDefault`, glem posisjonen, `scrollTo({ top: 0, behavior: 'smooth' })` på den
rullende boksen (chatlista) eller `window`.

## Sveip på rader uten å krangle med iOS

`public/sveip.js`, rene tall:
- De første **24 px fra venstre kant** tilhører iOS sin tilbake-gest: rør ikke
  hendelsen.
- Under **10 px** bevegelse: vent. Mer opp/ned enn sideveis: **rulling** — slipp raden
  med en gang.
- Knappen som kommer fram er 88 px; motstand forbi den (`KNAPP + (a − KNAPP) · 0,6`);
  «fullt» sveip ≥ 55 % av bredden sletter.
- `touch-action: pan-y` på raden.

## Bunnark

`apneArk({ tittel, innhold, valg })`: `role="dialog" aria-modal`, glir opp nedenfra,
`max-height: 85dvh`, `overscroll-behavior: contain`, safe-area i bunnen, låser kroppen
(`body.laast { position: fixed; overflow: hidden }` med `top: -scrollY` og
tilbakestilling ved lukking), lukkes ved `hashchange` så låsen ikke henger igjen etter
en kantsveip.

## Lyskasse (bilder i fullskjerm)

Samme kroppslås som arket — uten den ruller lista bak når fingeren drar på bildet, og
man kommer tilbake til et annet sted i albumet. Trykk hvor som helst lukker, unntatt på
`a, button, input, textarea` under bildet (bildetekst-felt, «spør agenten»-felt).
Fjern `hashchange`-lytteren i `lukk()` også — en `{ once: true }`-lytter som aldri fyrte
henger igjen etter vanlig lukking og kan fjerne kroppslåsen til en *senere* lyskasse.
