# Falske tjenester: av, falsk og ekte

Symptomer dette løser: testene trenger en konto for å kjøre; en test gikk mot den ekte
tjenesten; appen krasjer ved oppstart fordi en nøkkel mangler; ny nøkkel krever omstart;
feilmeldingen er `HTTP 403`.

## Tre moduser bak ett grensesnitt

Hver integrasjon er et lite grensesnitt med de operasjonene appen bruker, pluss
`status()`. Én funksjon velger implementasjonen fra miljøet:

```ts
export type Ark = {
  les(omrader: string[]): Promise<Lesing[]>;
  skriv(omrade: string, verdier: unknown[][]): Promise<{ oppdatert: number }>;
  status(): { paa: boolean; melding: string | null };
};

export function arkFraMiljo(data = DATA): Ark {
  if (process.env.APP_ARK === 'av') return avslaattArk('Regnearket er skrudd av (APP_ARK=av).');
  if (process.env.APP_ARK_FALSK) return falsktArk(process.env.APP_ARK_FALSK);
  return ekteFraFiler(data);   // oppsettsfiler i datamappa; mangler de, er det av med en melding
}
```

- **Av**: for en installasjon som ikke skal ha tjenesten, og for tester som ikke
  handler om den. Alle kall feiler med meldingen fra `status()`.
- **Falsk**: for testene og for å vise fram appen uten konto.
- **Ekte**: bare når oppsettet finnes. **Mangler oppsettsfila, er tjenesten av**, med
  en melding, ikke en krasj ved oppstart.

## `status()` sier hva som mangler

`{ paa: false, melding: 'Regnearket er ikke koblet til ennå. Se «Koble til» i deploy/README.md.' }`.
Innstillingene viser meldingen, API-et svarer med den, og agenten får den som feil når
den prøver et verktøy. Én setning, tre steder, ingen gjetting.

## Den falske tjenesten er en JSON-fil

- Samme grensesnitt, med tilstanden i en JSON-fil miljøflagget peker på. Skriving går
  tilbake til fila, så testen leser resultatet derfra.
- Oppfør deg som den ekte i kantene som betyr noe (Google kutter tomme rader og
  celler på slutten; det gjør den falske også), og feil med den ekte feilmeldingen
  (ukjent fane → «Fanen X finnes ikke. Fanene er: …»).
- `status()` som den ekte: finnes ikke fila, er tjenesten ikke koblet til.
- **Logg kallene** (én JSON-linje per kall i en fil ved siden av), så testen kan
  sjekke hva som faktisk ble sendt.
- **Feil utløses fra testen:** et bestemt ord i inndataene (`FEIL401`), eller at en fil
  finnes. Da testes feilveien med den ekte koden.

Det samme gjelder push: et miljøflagg peker på en fil, hver push blir en linje der, og
et endepunkt som slutter på `/dod-410` svarer som et dødt abonnement.

## Falske programmer

Kaller appen et program (en kode-CLI, et konverteringsverktøy), pek et miljøflagg
(`APP_CODEX=<sti>`) på et lite skript i `test/falsk-<navn>/` i stedet for å mocke
funksjonen som kaller det. Da kjører den ekte koden lenger ned: argumentene som bygges,
miljøet som sendes med, fila som leses etterpå.

Det falske programmet:

- gjør det minste som ser ekte ut (skriver resultatfila der det ekte ville skrevet den);
- logger argumentene, én linje per kall;
- logger **navnene** på miljøvariablene det fikk (`env | sed 's/=.*//'`), aldri
  verdiene, så testen kan bevise at serverens hemmeligheter ikke fulgte med;
- feiler som det ekte (exit 1 og den ekte teksten på stderr) når prompten har et
  bestemt ord;
- svarer på `--version`.

## Feilkoder blir setninger

Oversett tjenestens feil der de oppstår, med hva brukeren kan gjøre:

| Svar | Setning |
| --- | --- |
| 403 + «has not been used / is disabled» | API-et er ikke slått på i prosjektet til tjenestekontoen. Se «Koble til». |
| 403 ellers | Arket er ikke delt med tjenestekontoen `<e-post>`. Del det som redaktør. |
| 404 | Fant ikke arket med id `<id>`. Sjekk oppsettsfila. |
| 429 | Kvoten er brukt opp akkurat nå. Vent et minutt og prøv igjen. |
| 401 | Innloggingen ble avvist. Prøv igjen; virker det ikke, lag en ny nøkkel. (Nullstill token-cachen.) |

Setningen går rett til brukeren og til agenten, som da kan si hva som må gjøres i
stedet for å prøve igjen.

## Endret oppsett merkes uten omstart

Sjekk et avtrykk av oppsettsfilene ved hvert kall — `stat`, ikke lesing — og bygg
klienten på nytt når det endrer seg, eller når den forrige var av:

```ts
const avtrykk = () => FILER.map((f) => {
  const st = fs.statSync(path.join(mappe, f), { throwIfNoEntry: false });
  return st ? `${st.ino}:${st.size}:${st.mtimeMs}` : '-';
}).join('|');
let forrige = avtrykk(), klient = lagKlient();
const naa = () => {
  const na = avtrykk();
  if (na !== forrige || !klient.status().paa) [forrige, klient] = [na, lagKlient()];
  return klient;
};
```

Inode med, så en fil som byttes med `mv` (atomisk skriving) også merkes.

## Koble-skript

Hemmeligheten ligger på maskinen der den ble laget og skal til tjeneren. Et skript per
integrasjon, kjørt fra egen maskin:

- **Idempotent**: kan kjøres igjen med ny nøkkel eller nytt oppsett.
- Sjekker fila lokalt først (riktig type, de feltene som må finnes).
- **Sender hemmeligheten over ssh-stdin**, aldri i en kommandolinje (synlig i `ps`) eller
  via `/tmp`: `ssh vert "sudo bash -c 'umask 077; cat > $M/nokkel.json.ny && mv $M/nokkel.json.ny $M/nokkel.json'" < nokkel.json`.
  Skriv til `.ny` og `mv`, så appen aldri leser en halv fil.
- Ber appen lese på nytt og skriver ut **bare statusfeltet**, aldri data.
- Sier i toppen hvordan det angres.

## Testene

- Testoppsettet setter alle falske (`APP_ARK_FALSK`, `APP_CODEX`, …) og `av` for alt
  som ikke er under test, og starter en ekte server mot en tom datamappe.
- **Eget portområde per testfil.** `node --test` kjører filene parallelt, og to filer
  som starter servere på samme port, feiler av og til. Gi hver fil sitt område
  (f.eks. 3300–3309, 3310–3319), eller kjør med `--test-concurrency=1`.
- En test for hver setning i feiltabellen over, via feilordet i den falske.
