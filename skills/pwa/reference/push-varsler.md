# Push-varsler på iPhone

Symptomer: tillatelsen forsvinner etter noen ganger; varslene blir liggende i
varselsenteret; samme varsel tre ganger; varsel kl. 03; abonnementet peker på noe
som ikke er en pushtjeneste.

Referanse: `reiseapp/varsler.js` (utløsere, ren logikk), `server.js` (abonnement og
utsending), `public/varsler.js` (abonnering i nettleseren), `public/sw.js` (push og
klikk), `test/varsler.test.js`.

## Forutsetninger på iOS

- Bare for apper **lagt til på Hjem-skjermen**, og bare over **HTTPS med ekte
  sertifikat**. `tailscale serve --https=5443` gir Let's Encrypt for `*.ts.net`.
- Selve pushen går fra serveren til Apple (`web-push`-pakken, VAPID), ikke gjennom
  tailnettet — telefonene får den uansett hvor de er.
- VAPID-nøklene lages **én gang** og lagres i datamappa (`vapid.json`, mode 600): de
  er identiteten overfor Apple/Google; bytter du dem, må alle abonnementene fornyes.
- **Verten må aldri sove**: dvale maskert, lokket ignorert — ellers kommer aldri
  ferje-påminnelsen 08.55. Og serveren må nå Apple (utgående HTTPS).
- Hvert abonnement er én telefon; bryterne gjelder den telefonen. «Per bruker» = per
  telefon når appen ikke har innlogging.
- `Notification.requestPermission()` må kalles fra et trykk. Push API-et finnes ikke
  i Safari-fanen på iOS i det hele tatt. Si *hvorfor* det ikke kan slås på (`hindring()`):
  iOS uten installasjon (`navigator.standalone` / `display-mode: standalone`) → «Legg appen
  på Hjem-skjermen først», ingen `PushManager` → «støtter ikke», `permission === 'denied'`
  → «slå på i Innstillinger → Varsler». VAPID-nøkkelen kommer base64url og må bli
  `Uint8Array` (pad `=`, `-`→`+`, `_`→`/`, `atob`). Hvert abonnement får et enhetsnavn fra
  UA, så Innstillinger kan si «Andre enheter med varsler: iPhone». Abonner med
  `reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey })`,
  gjenbruk `getSubscription()` om det finnes.

## Service workeren MÅ vise noe

iOS krever at hver push faktisk viser et varsel — gjør den ikke det, **trekker Safari
tillatelsen etter noen ganger**. Derfor `showNotification` uansett, også om nyttelasten
er tom eller ødelagt:

```js
self.addEventListener('push', (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch { d = { tekst: e.data?.text?.() || '' }; }
  const tag = d.nokkel || 'app';
  // Samme sak skal erstatte det forrige varselet, men iOS gjør det ikke selv ut fra
  // `tag` (WebKit-feil 258922). Lukk de gamle med samme tag først.
  e.waitUntil(self.registration.getNotifications({ tag })
    .then((gamle) => gamle.forEach((v) => v.close()), () => {})
    .then(() => self.registration.showNotification(d.tittel || 'App', {
      body: d.tekst || '', icon: '/ikon-192.png', badge: '/ikon-192.png',
      tag, data: { url: d.url || '#/' },
    })));
});
```

## Klikk og lukking

- `notificationclick`: lukk varselet, fokuser et åpent vindu av appen og
  `navigate(url)`, ellers `clients.openWindow(url)`.
- **Varslene ble liggende i varselsenteret** når appen ble åpnet fra ikonet i stedet
  for fra varselet. Lukk alle viste varsler når appen kommer i forgrunnen
  (`reg.getNotifications().then(v => v.forEach(n => n.close()))` i `visibilitychange`
  /`focus` og ved oppstart), og lukk de andre når ett trykkes på.

## Serverens tre regler (i kode, ikke skjønn)

1. **Stille timer**: ingenting mellom 22 og 07 lokal tid der brukerne er
   (`Intl.DateTimeFormat` med `timeZone`, ikke serverens klokke).
2. **Hvert varsel én gang**: nøkkel per sak og dag (`program:<id>:<dato>`) i en logg
   i datamappa, så en omstart ikke sender alt på nytt. Nøkler eldre enn tre dager
   ryddes.
3. **Tak per døgn** (6): går det over, er det en feil i en utløser, og den skal
   bråstoppe i stedet for å tømme seg over telefonen.

## Utløsere som rene funksjoner

`UTLOSERE[navn](tur, naa, vaer) → [{ nokkel, tittel, tekst, url }]`. Bjelle per
programpunkt (`varsel: 0 | 15 | 30 | 60` minutter før, krever `tid`) slo én global regel
(«alle med klokkeslett 30 min før»): ferja trengte 30, middagen 0, og ingen kunne skru av ett
punkt. Migrering ved oppstart (`p.tid && p.varsel === undefined → 30`), ellers mistet alle
eksisterende punkter varselet stille. Hver får
tilstanden og klokka og svarer med det som er modent **akkurat nå**; de vet ingenting
om push. Vinduet er ti minutter bredt (`d > −5 && d <= 5`) så en runde hvert minutt
ikke kan bomme. `modne(tur, abonnement, naa, vaer)` filtrerer på brukerens valg — et
valg det ikke er tatt stilling til er **på**, slik innstillingsskjermen viser det (ellers
når en ny utløser aldri dem som alt abonnerer). Testes uten nettverk.

## Abonnementet

- Serveren godtar bare `endpoint` som er en URL hos en ekte pushtjeneste, høyst 1000
  tegn — ellers kan hvem som helst få serveren til å POST-e til hva som helst. Sjekken
  «begynner på https://» stoppet ikke `https://100.99.4.33/` eller
  `https://127.0.0.1:7666/`. Hvitlisten er på **vertsnavn**, sjekket før lagring og før
  sending:
  - eksakte verter (`web.push.apple.com`, `fcm.googleapis.com`,
    `updates.push.services.mozilla.com`) pluss bestemte underverter med punktum foran
    (`.push.apple.com`, `.notify.windows.com`), der verten må være lengre enn suffikset;
  - `https:` og ingen port, brukernavn eller passord i URL-en;
  - **ikke** et suffiks som `googleapis.com`: det slipper gjennom alle Googles API-er.
  Test `push.apple.com.angriper.no`, `evilgoogleapis.com` og
  `https://web.push.apple.com:8443/` (en naiv delstrengsjekk slipper de to første
  gjennom). Samme SSRF-mønster gjelder alt som tar imot en adresse utenfra (hente PDF,
  hente bilde).
- Samme `endpoint` igjen = oppdater valgene, ikke nytt abonnement.
- **404/410** fra pushtjenesten betyr dødt abonnement (appen avinstallert, tillatelse
  trukket): fjern det.
- **`urgency` og `TTL` per type**, ikke fast. Det tidskritiske (en frist, en
  påminnelse) sendes med `urgency: 'high'`, fordi Apple kan holde igjen `normal` til
  telefonen våkner av seg selv; det er en begrunnet antakelse, ikke målt. TTL kort for
  påminnelser (en time; for sent er verdiløst) og lengre for oversikter (et halvt døgn).

## Abonnementet holdes i live

- **Feil nøkkel:** har telefonen et abonnement laget med en annen `applicationServerKey`
  enn serverens nåværende (nye VAPID-nøkler, ny server), `unsubscribe()` og abonner på
  nytt. Sammenlign bytene i `ab.options.applicationServerKey` med nøkkelen.
- **Meld fra på nytt ved hver oppstart**, når telefonen har et abonnement: serveren
  behandler samme `endpoint` som en oppdatering, så det er gratis, og en server som
  har mistet det, får det tilbake.
- **`pushsubscriptionchange`** i service workeren: abonner på nytt med samme nøkkel og
  send det nye abonnementet med det gamle endepunktet (`erstatter`), så serveren
  bytter i stedet for å legge til. Fornyingen ved oppstart finnes fordi iOS kanskje
  ikke fyrer hendelsen.
- **Service workeren kan ikke lese `localStorage`.** Det den trenger for å melde fra
  (hvem telefonen tilhører), skrives av siden til en liten egen cache
  (`caches.open('app-meg')` → `put('/meg', new Response(navn))`) og leses der.

## Varsler med innhold fra en agent

Serveren bestiller teksten fra agenten i den delte samtalen (kl. 8 og 21.30), lagrer
den per dag (`tur.morgen[dato].tekst`), og utløseren sender **første avsnitt** uten
markdown (`ingress()`, maks 160 tegn, kuttet på ordgrense). Bestillingen tar 30–90 s,
så pushen går i neste minuttrunde. Tre tilstander per dag i `tur.<felt>[dato]`:
`{ hoppet }` når vilkåret sa nei (så det ikke vurderes hvert minutt), `{ bestilt }` mens
den går, `{ tekst, skrevet }` ferdig; feiler den, slettes markøren så neste minutt prøver
igjen innenfor vinduet. Markøren settes **før** første `await`, ellers bestiller to
minuttrunder dobbelt. **Virket ikke:** kveldspush som dytt («Skriv dagen mens den er
fersk») — et varsel som ber om arbeid. Nå gjør agenten arbeidet, og pushen sier «Dagen er
skrevet», så brukeren retter i stedet for å produsere.

## Det siste leddet kan bare en iPhone teste

At Apple faktisk vekker telefonen. Derfor «Send et testvarsel» i Innstillinger
(`POST …/varsler/:id/test`). Alt før det — push-hendelsen mot SW-en med og uten
nyttelast, utløserne, dedupe — er testet uten telefon.

## Ikonmerke

`navigator.setAppBadge(n)` med noe brukeren kan gjøre noe med (ugjorte punkter i
dag), oppdatert ved hver visning. `clearAppBadge` når null.

Merket er et produktvalg, ikke en regel. Et tall som bare vokser, blir støy; en annen
app valgte å rydde merket ved hver push (`clearAppBadge` i push-handleren) og la
varselet selv bære beskjeden.
