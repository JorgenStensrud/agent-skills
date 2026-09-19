---
name: fotoalbum
description: >-
  Gjøre et haug med telefonbilder til en trykkeklar fotobok som ser bevisst ut:
  planlegge side for side i stedet for mekanisk, vurdere hvert bilde, finne
  duplikater kontra serier, velge maler og layout uten beskjæring, og kjøre runden
  på nytt når det kommer flere bilder. Bruk også når en generert bok «ikke blir helt
  perfekt».
---

# Fotobok av et album

Fra `reiseapp` sin fotobok: hundre telefonbilder fra ni dager til en A4-liggende PDF
for Peecho/Prodigi. Det som står her er det som faktisk skiftet boka fra mekanisk til
bevisst, og det som ble prøvd og forkastet på veien.

## Den ene innsikten

**Skill planen fra tegningen.** Nesten alle dårlige autogenererte album har samme
årsak: layout og rendering skjer i samme pass, så det finnes ingenting å se på, rette
eller låse — bare inndata. Gjør planen til data:

```js
{ versjon: 1, sider: [
  { mal: 'omslag',  bilder: ['a1'] },
  { mal: 'apner',   dato: '2026-09-12', bilder: ['b2', 'c3'] },
  { mal: 'dagtekst', dato: '2026-09-12', nr: 2 },
  { mal: 'helside', dato: '2026-09-12', bilder: ['d4'], laast: true },
] }
```

Da kan en algoritme legge førsteutkastet, et menneske eller en agent redigere det,
sider låses, og alt nedenfor forbli rent og testbart. Uten dette kan du bare lappe.

## Den andre innsikten

**Geometri er ikke dømmekraft.** En layoutalgoritme kjenner bredde og høyde. Den vet
ikke at ett bilde er turens beste og et annet en kvittering, så den gir dem like mye
plass. Resultatet er at solnedgangen står like stor som et Monopol-brett.

Legg derfor en vurdering på hvert bilde, satt av noen som har *sett* det:

| Felt | Verdier | Brukes til |
| --- | --- | --- |
| `styrke` | `sterk`, `ok`, `svak` | hvem som får hele sida; svake foreslås ut |
| `kategori` | mat, utsikt, portrett, ossto, sjoen, byen, hotell, aktivitet, detalj, dokument | temasidene bakerst |
| `foreslattUt` | kort grunn | forslag til brukeren, aldri automatisk fjerning |
| `skjul` / `behold` | ja/nei | svaret deres: ute, eller aldri foreslå igjen |

**Virket ikke:** lengden på bildeteksten som mål på kvalitet. Den ga hele sida til et
solbrillestativ med teksten «Who is that?». Bruk den bare som reserve når ingen har
vurdert bildene.

**Virket ikke:** å utlede tema fra klokkeslettet. «Timen før mørket» ble koffert,
hotellrom og Monopol, fordi alt var tatt mellom 18 og 20. Et tema om hva bildene
*viser* krever at noen har sett dem. Vet du bare klokka, si bare det («Kveldene»).

## Duplikat eller serie

Det viktigste skillet, og det eieren vil ha en mening om:

- **Duplikat:** samme motiv, samme uttrykk. Bare det beste skal med.
- **Serie:** samme motiv, *ulikt uttrykk*. Tre ansikter over den samme focacciaen er
  gøy ved siden av hverandre, i tett stripe, like store.

Mekanisk kan du skille dem med en dHash: avstand ≤ 6 er duplikat, 6–18 med minst ett
par tydelig fra hverandre er serie. Men kategorien lyver: et bilde av et ansikt bak en
focaccia er merket `mat`, ikke `portrett`, så en regel som «minst to portretter» bommer
på nettopp de gruppene eieren vil ha. **Se på dem, eller spør.**

**Virket ikke:** å la Historien/galleriet kollapse like motiv før boka ser dem. Da kan
en serie aldri oppstå, fordi de ekstra utsnittene alt er borte. Flytt motivgrupperingen
inn i planen: ett per motiv som standard, men står bildene i en registrert serie, blir
alle med.

## Layout uten beskjæring

Eieren vil sjelden ha bildene beskåret. Da kan en side aldri fylles helt med blandede
formater, og jobben blir å velge den minst tomme løsningen.

```js
// Prøv alle sammenhengende raddelinger (1–3 rader, ≤4 per rad).
// Hver rad fyller bredden → h = (bredde - gap*(n-1)) / Σ(bredde/høyde)
// Blir stabelen for høy, krymp alt likt: f = min(1, sidehøyde / total)
// dekning = f² · Σh / sidehøyde
// poeng   = dekning · (0.85 + 0.15·f)   ← påslag for rader som når begge margene
```

Det siste leddet betyr noe: to layouter med samme dekning ser ulike ut, og den som
berører begge margene ser bevisst ut mens den krympede flyter. Og dekker den beste
utleggingen under halvparten av sida, er **to romslige sider bedre enn én trang** —
del gruppa i stedet.

Malvokabularet som holdt: `helside` (én), `rad` (2–3), `serie` (3–5 tett), `rutenett`
(4–6), `tema`, pluss oppslagets `apner` + `dagtekst` og sidene som fyller opp.

**Virket ikke:** «ett stort og tre små ved siden». Et liggende heltebilde og stående
småbilder kan ikke matche høyde uten at de små blir frimerker (35 mm mot 220 mm).
Gi helten sin egen side i stedet, og legg resten i justerte rader.

**Virket ikke:** toppstilte bildesider med en tegning i hullet nederst. Ved siden av
ekte bilder ser en strektegning ut som en feil. Sentrer radene i flata og la luften
være symmetrisk — og bruk ekte sider (kart, program, register) som skilleark når et
oppslag må skyves én side.

## Grupper etter hendelse, ikke etter antall

En side blir «frokosten» i stedet for «seks urelaterte ting» hvis du deler bildene på
tidsopphold: mer enn 20–25 minutter mellom to bilder starter en ny side. Så to til seks
per side; ett bilde alene bare når det fortjener hele sida.

## Forslag, aldri automatisk sletting

Ingenting forsvinner uten at eieren har sagt ja. Mønsteret:

1. Samle forslag (duplikater, dokumenter, svake) med en kort, lesbar grunn.
2. Vis dem som småbilder med grunn og to knapper: **Ta ut** og **Behold**.
3. `Ta ut` → `skjul`. `Behold` → `behold`, og forslaget kommer aldri igjen.
4. Si tydelig at bildet blir liggende i albumet uansett; det er bare boka det går ut av.

En kontaktkopi (alle forslagene som ett PNG, servert fra appen) er en billig måte å
vise dem på telefonen mens skjermen bygges.

## Å kjøre runden på nytt

Det kommer alltid flere bilder. Gjør runden inkrementell og selvbetjent:

- Lagre vurderingen på bildet, ikke i en kjøring. Da er «hvilke er ikke vurdert?» et
  oppslag, og en ny runde koster bare de nye bildene.
- La agenten i appen gjøre den: `hent_uvurderte_bilder` → `se_bilde` per bilde →
  `vurder_bilde` → `foresla_bilde_ut` / `lag_serie` → `bygg_fotobok`. Én
  skråstrek-kommando (`/album`) starter hele runden.
- Låste sider overlever en ny plan, så det som er godkjent ikke rives opp.
- La signaturen som avgjør «er boka gammel» dekke **alt** som tegnes: bilder, tekster,
  vurderinger, serier, låste sider og layoutversjonen. Glemmer du ett felt, står boka
  og påstår at den er fersk.

For et engangsløft av et stort album er tre parallelle gjennomganger à 30 bilder
raskere enn én lang: hver skriver en tabell (id, hva bildet viser, styrke, kategori,
merknad) pluss en liste over nesten like grupper, og resultatet flettes inn etterpå.

## Trykk

A4 liggende (297 × 210) med 3 mm utfall, enkeltsider, RGB, partall sider, side 2 og
siste blank, minst 24 sider. HTML og CSS med `@page` + headless Chrome
(`Page.printToPDF`, `preferCSSPageSize`) gir bedre kontroll enn et PDF-bibliotek, og
kan forhåndsvises i nettleseren. `pdftoppm -r 50` lager sidebilder til appen. Skrifter
må inn med `@font-face` og `file://`, variable med `format('woff2-variations')` og et
vektspenn — sjekk med `pdffonts`. Se skillen `pwa` for Chrome-flaggene og fellene.
