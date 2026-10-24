# Chat og strømmede svar i en PWA

Symptomer: tråden rykker til bunns for hver tekstbit så det er umulig å lese; svaret
kommer på én gang; `**stjerner**` i svaret; man kan ikke rulle i chatten; tråden
kuttes hardt mot kantene.

Referanse: `reiseapp/public/spor.js`, `markdown.js`, `format.js`, `rull.js`,
`agent/samtaler.js` (server). Det er `EventSource` over vanlig HTTP, ingen websockets.

## Strømmen

- Nettleseren sender med `POST` og får **alt** tilbake på én åpen `EventSource`
  (`GET …/hendelser`). Serveren fanUt-er hendelser til alle lyttere — begge
  telefonene ser samme tråd i samme sekund.
- **Første hendelse er hele tilstanden** (`tilstand`: meldinger, kø, opptatt). Den
  kommer på nytt hver gang strømmen har vært brutt (telefonen i lomma). Da tegnes alt
  fra bunnen av — men **posisjonen beholdes** hvis man sto og leste (`scrollTop`
  gjenopprettes i `requestAnimationFrame`).
- Ellers er DOM-en **append-only**: en boble byttes aldri ut mens den fylles;
  `tekst`-hendelser `append`-er, `melding_slutt` erstatter med serverens endelige
  tekst, formatert.
- SW-en og gzip må slippe strømmen forbi (service-worker.md). Hendelses-id-er lages
  i nettleseren ved sending, så kø-bobler og de ekte meldingene kan kobles.
- Én strøm om gangen: forrige lukkes når en ny åpnes og ved `hashchange` bort.
- **Virket ikke:** én `fetch`-strøm per spørsmål (POST + `body.pipeThrough(TextDecoderStream)`
  fordi `EventSource` ikke kan POST-e). Det virket, men agenten døde med HTTP-kallet og
  nettleseren måtte eie historikk og kø. POST + egen `EventSource`-GET er svaret.
- `res.on('close', () => abort())` på strømruta: lukker telefonen fanen, skal agenten
  slutte å bruke tokens på et svar ingen leser.
- Ids: serveren stempler meldingen idet den sendes (`Math.max(Date.now(), siste + 1)`, aldri
  samme to ganger); Pi setter sitt eget tidsstempel senere, så en `ventende`-FIFO parer
  `message_start` med id-en nettleseren alt har. Kø-bobler ligger alltid sist (`insertBefore`
  første `.venter-tur`) — `koet` kommer i praksis *før* svaret på forrige spørsmål starter.
- Pi tømmer kø-meldinger inne i samme kjøring: `agent_end` kommer **én** gang, ikke én per
  svar. Skill svarene på `melding_slutt`; en boble uten tekst der fjernes.
- Et `opptatt`-flagg på serveren dekker gapet mellom `prompt()` og `isStreaming` (minnet
  gjør sitt før første modellkall) — ellers ble to meldinger tett i tett to kjøringer.
- Visningen tegnes **ikke** på nytt ved forgrunn/oppfrisking — det ville kastet
  tråden man leste i. Data hentes likevel, så kopien er fersk når man går videre.

**Serveren eier samtalen; nettleseren er en tynn tegner** (bobler nøkla på id, ingen
historikk, ingen kø). **Virket ikke:** kø og historikk i nettleseren — feltet ble
stående med teksten (dobbel sending), tråden ble bygd på nytt midt i strømmen så
svaret skrev til en løsrevet node og «frøs», TDZ-feil, kø-bobla la seg *før* svaret som
alt var startet. Den tredje lappen ble erstattet av ombygging: én levende sesjon per
samtale på serveren, `followUp()` for meldinger som kommer mens et svar strømmer.
Felles samtale på tvers av telefoner: «opptatt» settes straks *noen* melding starter,
ellers ser telefon B ledig ut i sekundene før første ord.

**Ytelse per bit:** legg biten til (`append`), aldri `textContent = alt så langt`
(kvadratisk, 130 biter × hele strengen). Autovekst på feltet måles høyst én gang per
`requestAnimationFrame`, ikke per tastetrykk (40 tastetrykk → 13 ms).

**DOM-feller uten telefon:** `replaceChildren(null)` skriver teksten «null»,
`replaceChildren(undefined)` «undefinedundefined», `el('p', { class: null })` gir
`class="null"`. `filter(Boolean)` på barn, betingede attributter.

## Følg bunnen bare når man står der

Regelen fra Meldinger: `naerBunn({ scrollTop, scrollHeight, clientHeight }, 80)`.
`fulgte` settes på hver `scroll`; en ny bit ruller bare hvis `fulgte`. Ruller man opp,
står lista, og en knapp «↓ Nytt nederst» tar en ned (`tilBunn(true)` = egen handling,
mykt; strømmen ruller uten `behavior: 'smooth'`). Høyst én rulling per ramme
(`requestAnimationFrame`-vakt). Lange svar får «↑ Til toppen av svaret» når bobla er
høyere enn 90 % av lista.

**Virket ikke:** `tilBunn()` på hver tekstbit. Svaret strømmer i minutter, og hver bit
dro lista til bunns. Tre runder: (1) hopp til bunns per bit slåss med tastaturet, (2)
`scrollIntoView` uten animasjon var bedre men rykket fortsatt, (3) `naerBunn` holdt.

- **Tråden starter nederst, uten å synes.** Rull til bunns *før første tegning*: i React
  i `useLayoutEffect`, ikke `useEffect`, ellers ser man toppen av tråden et øyeblikk
  før den hopper.
- **Når feltet får fokus**, rull til bunns *etter* at tastaturet står (en kort
  `setTimeout`, ~250 ms), ellers havner siste melding bak tastaturet.

## Chatten er et fast panel

Se navigasjon.md: panelet er `fixed`, bare `.samtale` ruller, `overscroll-behavior:
contain`. Med `html { overscroll-behavior: none }` tok ikke pull-to-refresh fingeren
lenger. Skrivefeltet: `<textarea rows=1>` med `autocapitalize="sentences"`.

**Enter avhenger av tastaturet.** Med mus og fysisk tastatur sender Enter (Shift+Enter
gir linjeskift). På berøringsskjerm (`matchMedia('(pointer: coarse)')`) gir Enter
linjeskift, og bare knappen sender, som i ChatGPT: på telefonen er Enter den eneste
måten å lage et avsnitt på. Sett da ikke `enterkeyhint="send"`.

## Myke overganger

- Tråden tones ut mot overskriften og skrivefeltet:
  `mask-image: linear-gradient(to bottom, transparent 0, #000 16px, #000 calc(100% - 18px), transparent 100%)`
  (+ `-webkit-mask-image`), med litt ekstra padding topp/bunn.
- Nye bobler glir inn (`.ny` med `animation: boble-inn 0.32s`), men bare det som
  kommer inn **mens man ser på** — tråden som tegnes ved oppkobling står stille, ellers
  blafrer alt ved hver forgrunn. `prefers-reduced-motion` respekteres.
- Forslag/snarveier bare når tråden er tom, og de tones ut (`transition: opacity`)
  ved første melding. En fast rad med forslag over feltet var støy. Utoning med
  `transitionend` → `remove()` **og** `setTimeout(400)` som reserve: `transitionend` kommer
  ikke ved `prefers-reduced-motion`, og da lå forslagene igjen under boblene.

## Formatering uten innerHTML

`markdown.js`: en liten tolker (avsnitt, lister, overskrifter, fet, kursiv, kode,
lenker, bilder) til et tre; `format.js` bygger DOM med `el()`. Modellens tekst går
aldri gjennom `innerHTML`. To måter å strømme på:

- **Ren tekst til svaret er ferdig** (`white-space: pre-wrap`), og formatering ved
  `melding_slutt`. Enkelt, men svaret hopper når det formateres.
- **Formatér mens det strømmer**, med det uferdige lukket før tolkningen: et halvt
  `**` eller en halv `` ` `` lukkes, en åpen kodeblokk får et avsluttende gjerde, og en
  påbegynt tabellrad (uten avsluttende `|`) holdes tilbake til den er hel. Tegn høyst
  én gang per `requestAnimationFrame`. Da står formateringen riktig fra første tegn,
  og ingenting hopper når svaret er ferdig. Lukkingen er en ren funksjon, testet i node.

- Stjerner og understreker midt i ord (`snake_case`, `2*3*4`) er ikke formatering:
  lookbehind/lookahead på ordtegn i regexen.
- Bilder `![alt](url)` bare fra eget opphav med en fast sti (`/mini/<id>`) — aldri
  `https://` utenfra, `javascript:` eller `data:`. Et bilde lastes uten at noen trykker,
  så en ekstern bilde-URL i modelltekst kan sende data ut i det øyeblikket svaret
  tegnes. Vises som småbilde i en `<button>` som åpner lyskassa med originalen. Et
  avsnitt som bare er bilder blir en rad.
- Lenker `target="_blank" rel="noopener"`; bare `http(s)`.
- **Lenkevern for modelltekst.** En modell som har lest en nettside eller en e-post,
  kan være styrt av den, og en lenke lekker på ett trykk — også med en kort sti eller
  et underdomene (`https://saldo-12345.angriper.no/`), så formen på URL-en avgjør
  ingenting. Klikkbar bare når den eksakte URL-en står i brukerens egne meldinger;
  ellers hele adressen som tekst med det ekte vertsnavnet, og åpning etter et ja.
  Detaljene: skillen `agent-i-appen`, reference/fremmed-tekst.md («Hver vei ut»).

## Skråstrek-kommandoer

«/» åpner lista, filtrert mens man skriver; piltaster, Enter sender, Tab setter inn,
Esc lukker, og fingertrykk velger uten at tastaturet lukkes. Serveren eier lista
(`GET /api/kommandoer`) og **utvider** kommandoen til en hel setning før den går til
modellen. Systemkommandoer (`/nytt`, `/stopp`) håndteres av serveren og når aldri
modellen — før det svarte modellen «Samtalen er tømt» på `/clear` uten at noe skjedde.

## Bilder inn i chatten

Krymp i nettleseren før sending (høyst 1600 px JPEG): et telefonbilde er 3–12 MB.
HEIC fra iPhone blir JPEG på veien gjennom canvas (780×1688 → 142 KB).
`createImageBitmap(fil, { imageOrientation: 'from-image' })` retter EXIF-rotasjonen; bildene
går ut igjen til begge telefonene som `data:`-URL-er i hendelsene, og i konteksten til
modellen beholdes bare de to siste brukermeldingenes bilder (~1 500 tokens hver, hver gang).
Et bilde uten tekst er også et spørsmål («Se på bildet.»), ikke 400. Den globale
`express.json()` (100 kB) må hoppes over for bilderuta, ellers 413 før ruta ser noe —
og test grensa med en kropp som faktisk er stor (600 kB), små testbilder så den aldri.
`createImageBitmap` der det finnes (retter EXIF-rotasjon), ellers `<img>`-veien
(Safari). Høyst fire per melding, egen JSON-grense på ruta (24 MB), server validerer
mimetype og base64.

**Filer fra iPhone har ofte tom `File.type`**, særlig `.md` og `.csv`. La endelsen
avgjøre når typen mangler, både for bilder og for tekstfiler, ellers avvises en
gyldig fil som «ukjent type».

## Andre sider sender ferdige spørsmål

En knapp på Dagbok/Historien POST-er en ferdig instruks til samtalen («Skriv dagboka for
14. september (2026-09-14) … lagre med skriv_dagbok») og hopper til Spør. Agenten slipper
å gjette hvilken dag «i går» var, svaret strømmer inn der samtalen alt står, og skrivingen
går gjennom verktøy — aldri en egen agentkjøring utenom samtalen. Verktøysteg telles i
statuslinja («Søker på nettet … (7. steg)»): tretti kall på fem minutter ser ellers ut som
stillstand.

## Meldinger fra appen selv

Bestillinger appen sender til agenten (morgenmelding kl. 8, kveldsskriving 21.30)
merkes `[app]` først i teksten; første linje etter merket vises som en liten linje midt
i tråden (`.app-linje`), ikke som en boble fra en bruker. Serveren venter på svaret
(`sporOgVent`) og sender første avsnitt som push. Bestillingen lagres per dag
(`tur.morgen[dato]`) så en omstart ikke bestiller to.

## Testing

`scripts/skjerm-fake-strom.mjs` bytter ut `EventSource` med en falsk som spiller av
en JSON-liste av hendelser: tom tråd, lang tråd, app-linje, feil — uten agent eller
innlogging. Fabrikkér `tilstand`-hendelsen og se at forslag vises bare når den er tom.
