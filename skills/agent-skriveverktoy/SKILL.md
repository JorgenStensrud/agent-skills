---
name: agent-skriveverktoy
description: >-
  Gi en agent inne i en app lov til å endre delte data: skriveverktøy mot appens eget
  API (tool use / function calling som legger til, retter, haker av eller sletter), hva
  systemprompten må si, en politikk som håndheves i kode, og testing uten API-nøkkel.
  Mønsteret er fra en Pi-agent, reglene gjelder ethvert verktøybrukende LLM-oppsett.
---

# Skriveverktøy til en agent i en liten app

Utgangspunktet: en liten app med én server, delte data og en agent i en fane som
hittil bare har lest. Nå skal den kunne endre noe. Ekte eksempel: `~/dev/reiseapp`
— `agent/verktoy.js`, `agent/politikk.js`, `agent/reiseagent.js`, `test/agent.test.js`.

Skrivingen er ikke det vanskelige. **Tilliten er det vanskelige.** En agent som
endrer delte data uten et bekreftelsessteg kan gjøre noe helt riktig og likevel
ødelegge tilliten, hvis brukerne oppdager det først to dager senere.

## 1. Skriv gjennom appens eget API

Fristelsen er å la verktøyet skrive rett i lagringen — den samme `db`-modulen eller
JSON-fila som serveren bruker. Ikke gjør det.

```js
// nei
tur.plan.push({ id: nyId(), dato, tekst });
lagre();

// ja
await fetch(`${basisUrl}/api/turer/${turId}/plan`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ dato, tekst }),
});
```

Fire grunner, i rekkefølge:

1. **Validering finnes allerede.** Serveren avviser tomme tekster, ukjente id-er og
   datoer på feil format. Skriver du utenom, må du gjenta alt — og glemme noe.
2. **Ett sted skriver.** Holder serveren dataene i minnet og lagrer atomisk, blir en
   agent som skriver ved siden av en tapt oppdatering neste gang serveren lagrer.
3. **Agenten ser det brukerne ser.** Leseverktøyet henter fra samme endepunkt som
   telefonene, med samme kuraterte innhold påført. Skriv samme vei, så er det ingen
   forskjell mellom det agenten tror den gjorde og det appen viser.
4. **Det er testbart.** Du kan starte en ekte server mot en tom datamappe og kjøre
   verktøyene mot den. Se punkt 6.

Motforestillingen — «det er et HTTP-kall til oss selv» — er riktig og uten
betydning. Det er localhost, det er millisekunder, og det er én kodesti i stedet for
to.

## 2. Formen på et verktøy

Pi vil ha `name`, `label`, `description`, `parameters` (typebox) og `execute`.

```js
import { Type } from '@earendil-works/pi-ai';

export function leggTilIProgrammetVerktoy(basisUrl, turId) {
  return {
    name: 'legg_til_i_programmet',
    label: 'Legger til i programmet',   // det brukeren ser strømme, ikke navnet
    description:
      'Legg et nytt punkt inn i programmet på en bestemt dato. Punktet dukker opp ' +
      'på begge telefonene med en gang. Legg inn det de ba om, ett punkt per ting, ' +
      'og si etterpå hva du la inn og på hvilken dato.',
    parameters: Type.Object({
      dato: Type.String({ description: 'Datoen punktet hører til, som ÅÅÅÅ-MM-DD' }),
      tekst: Type.String({ description: 'Hva som skal stå i programmet' }),
      sted: Type.Optional(Type.String({ description: 'id-en til et sted, hvis ett passer' })),
    }),
    async execute(_id, { dato, tekst, sted }) {
      const punkt = await api('POST', `/api/turer/${turId}/plan`, { dato, tekst, sted });
      return endring(`La «${punkt.tekst}» inn i programmet ${norskDato(punkt.dato)}.`, { punkt });
    },                                          // ↑ `endring` står i punkt 3
  };
}
```

Tre ting som er lette å ta feil av:

**`label` er brukergrensesnitt.** Hendelsen `tool_execution_start` bærer bare
`toolName`. Slå opp verktøyet i agentens egen liste og stream `label` — «Legger til i
programmet», ikke `legg_til_i_programmet`. Det er ofte det *eneste* brukeren rekker å
se før svaret kommer, og det er det første leddet i at endringen ikke er stille.

**`description` er prompt, ikke dokumentasjon.** Skriv når verktøyet skal brukes,
hva det *ikke* skal brukes til, og at agenten skal rapportere etterpå. Feltet leses
av modellen hver eneste gang.

**`execute` skal kaste ved feil.** Ikke pakk feilen inn i `content` som om alt gikk
bra. Agentloopen fanger unntaket, lager et verktøyresultat med `isError: true` og
mater det tilbake — modellen ser at det gikk galt og kan si det. Koder du feilen inn
i et vellykket resultat, må modellen *lese* seg til det, og noen ganger gjør den ikke
det.

```js
async function api(metode, sti, kropp) {
  const svar = await fetch(basisUrl + sti, { method: metode, ... });
  if (!svar.ok) {
    // Serveren svarer { feil: '...' }. Den setningen er mer nyttig for modellen
    // enn statuskoden, så den blir feilmeldingen.
    const kropp = await svar.json().catch(() => null);
    throw new Error(kropp?.feil || `${metode} ${sti} feilet: HTTP ${svar.status}`);
  }
  return svar.status === 204 ? null : svar.json();
}
```

## 3. Verktøyresultatet er manus for svaret

Regelen «agenten skal si hva den endret» holder ikke som prompt alene. Modellen
skriver sin egen versjon, og *da* begynner den å pynte: runder av datoen, generaliserer
teksten, sier «jeg har oppdatert programmet ditt» uten å si med hva.

Løsningen er å levere setningen ferdig:

```js
const endring = (sammendrag, felt) => ({
  content: [{ type: 'text', text: JSON.stringify({ endret: true, sammendrag, ...felt }) }],
  details: { sammendrag },
});

return endring(`La «${punkt.tekst}» inn i programmet ${norskDato(punkt.dato)}.`, { punkt });
```

Da er jobben til modellen å gjenta, ikke å formulere. Returner i tillegg hele objektet
serveren svarte med, så agenten har id og felter hvis brukeren spør videre.

**Ved endring: returner også den gamle verdien.** `forrigeTekst` gjør at agenten kan
si «fra X til Y», og brukeren ser hva som forsvant. Ved sletting: returner hele det
slettede objektet.

## 4. Hva systemprompten må si

Skriv reglene inn som en egen bolk, og si uttrykkelig at de går foran. Disse seks er
de som betyr noe:

- **Hent tilstanden før du endrer noe.** Id-ene ligger der, og agenten skal vite hva
  som allerede er lagt inn før den legger til mer. Ellers får du duplikater.
- **Si hva du endret, hver gang**, med de identifiserende feltene (dato og tekst, ikke
  «et punkt»). Vis til `sammendrag`-setningen fra verktøyet.
- **Slett aldri noe som ikke er uttrykkelig bedt om.** Navngi omskrivningene som
  *ikke* er fullmakt til å slette: «bytt ut», «flytt», «rydd opp».
- **Finn aldri på oppføringer.** Foreslå gjerne — men vent på ja før du skriver.
- **Tvetydige datoer bekreftes, ikke gjettes.** «På lørdag», «i morgen», «neste gang
  vi er der». Regn ut, si hvilken dato du kom til, eller spør.
- **Feiler et verktøy, si det rett ut** og si hva som ikke ble gjort. Aldri svar som
  om endringen gikk gjennom.

## 5. Steng de farlige kantene i koden, ikke bare i prompten

Prompten er en oppfordring. Koden er en regel. To mønstre er verdt jobben:

**Idempotent DELETE er en felle for agenten.** Et REST-API svarer gjerne 204 på
sletting av noe som ikke finnes — riktig for en nettleser som trykker to ganger, farlig
for en agent som har funnet på en id. Den melder «slettet» om noe som aldri fantes.
Slå opp først:

```js
const punkt = tur.plan.find((p) => p.id === id);
if (!punkt) throw new Error(`Fant ikke noe punkt med id ${id}. Hent turen og bruk en id derfra.`);
await api('DELETE', `/api/turer/${turId}/plan/${id}`);
return endring(`Slettet «${punkt.tekst}» ...`, { slettet: punkt });
```

Oppslaget trengs uansett for å kunne rapportere hva som forsvant. Det er samme kall.

**Avvis det som ligger utenfor domenet, med grensen i feilmeldingen.** En dato utenfor
reisen er nesten alltid en regnefeil hos modellen, ikke et ønske:

```js
if (dato < tur.fra || dato > tur.til) {
  throw new Error(`${dato} er utenfor reisen, som varer ${tur.fra}–${tur.til}. Spør hvilken dag de mener.`);
}
```

Feilmeldingen er prompt. Sier den *hva* som er galt og *hva* agenten skal gjøre nå,
retter den seg selv eller spør. Sier den bare «ugyldig dato», prøver den en ny gjetning.

**Velg et smalt utvalg verktøy.** Speil ikke API-et. Gi agenten det brukeren ba om og
ikke mer, og skriv begrunnelsen i koden. I reiseapp kan agenten legge til, rette og
hake av i alle listene, men bare *slette* i programmet — ønskelista og pakkelista
vokser eller krysses av, og tømmes i appen av et menneske som ser hele lista. Det er
lett å legge til et verktøy senere, og ubehagelig å ta et tilbake.

## 6. Test hele loopen uten legitimasjon

Dette er hele poenget med å skrive gjennom API-et: du kan teste det ordentlig.
Pi har en faux-provider som spiller av svar du selv bestemmer, så loopen kjører ekte
— ekte verktøy, ekte HTTP, ekte lagring — uten en eneste token.

```js
import { createModels, fauxProvider, fauxAssistantMessage, fauxToolCall, fauxText }
  from '@earendil-works/pi-ai';

const faux = fauxProvider({ tokensPerSecond: 10000 });
const models = createModels();
models.setProvider(faux.provider);

const agent = lagAgent({ models, model: faux.getModel(), basisUrl: BASE, turId });
faux.setResponses([
  fauxAssistantMessage([fauxToolCall('legg_til_i_programmet',
    { dato: '2026-09-14', tekst: 'Ferje til Limone 10.30' })], { stopReason: 'toolUse' }),
  fauxAssistantMessage([fauxText('Gjort.')]),
]);
await agent.prompt('legg inn ferja på mandag');
```

Forutsetningen er at agentbyggeren tar `models` og `model` som **parametre** i stedet
for å slå dem opp inni seg. Gjør den ikke det, kan den ikke testes; det er verdt
refaktoreringen.

Start en ekte server mot en midlertidig datamappe — `spawn(process.execPath,
['server.js'], { env: { ...process.env, PORT, <DATAVARIABELEN>: mkdtempSync(...) } })`,
og la serveren seede seg selv som ved første oppstart. Assert så på tre nivåer:

1. **Disk.** Les lagringsfila og finn oppføringen. Det beviser at skrivingen gikk hele
   veien ned, ikke bare returnerte pent.
2. **Verktøyresultatet.** `sammendrag` må inneholde de identifiserende feltene — det
   er det agenten kommer til å si.
3. **Feil er feil.** Kall verktøyet med en id som ikke finnes og assert
   `resultat.isError === true`. Det er testen som fanger den idempotente DELETE-fella.

Én ting til, gratis: assert på etikett-hendelsene, så du oppdager at statuslinja i
appen sier `legg_til_i_programmet` til brukeren.

**Kall aldri den ekte agenten i en test.** Den bruker et delt abonnement med kvote.

## 7. Politikken som utvidelse: håndhev i kode, før kallet

Punkt 5 stenger kantene *inne i* hvert verktøy. Men «slett aldri noe de ikke har bedt
om» kan ikke et verktøy avgjøre — det vet ikke hva brukeren skrev. Det er en regel om
*samtalen*, og den hører hjemme ett sted som ser hele samtalen og kjører før hvert
kall. I pi-coding-agent er det en utvidelse med en `tool_call`-håndterer:

```js
// agent/politikk.js — generelt, ingenting app-spesifikt
export function lagPolitikk({ tillatt, sletter = [], leser = [], journal }) {
  return (pi) => {
    pi.on('tool_call', (h, ctx) => {
      if (!tillatt.includes(h.toolName))
        return { block: true, reason: `Verktøyet ${h.toolName} er ikke tillatt i denne appen.` };
      if (sletter.includes(h.toolName) && !brukerenHarBedtOmSletting(ctx.sessionManager))
        return { block: true, reason: 'Sletting krever at brukeren selv har skrevet «slett», «fjern» … Spør, og be dem bekrefte med ett av ordene.' };
    });
    pi.on('tool_result', (h) => {
      if (journal && !leser.includes(h.toolName) && !h.isError)
        journal({ tid: new Date().toISOString(), verktoy: h.toolName, inn: h.input, sammendrag: h.details?.sammendrag });
    });
  };
}
```

`ctx.sessionManager.getBranch()` gir hele tråden; se på de **to** siste
brukermeldingene, ikke én — «Fjern X» → «Mener du …?» → «Ja» skal gå gjennom, «Rydd
opp» skal ikke. Et blokkert kall blir et verktøyresultat med `isError` og `reason`
som tekst, så modellen får en grunn den kan handle på — skriv grunnen som en
instruks («spør hva som skal bort»), ikke som en feilkode.

Sesjonen settes opp slik at *bare* dette gjelder:

```js
const loader = new DefaultResourceLoader({
  cwd, agentDir, settingsManager,
  noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true,
  systemPromptOverride: () => SYSTEM,
  extensionFactories: [politikk, historikk],   // historikk: pi.on('context', …) som trimmer
});
await loader.reload();
const { session } = await createAgentSession({
  cwd, agentDir, modelRuntime, model,
  noTools: 'builtin', customTools: verktoyene,
  resourceLoader: loader, settingsManager: SettingsManager.inMemory({ followUpMode: 'one-at-a-time' }),
  sessionManager: SessionManager.open(fil) /* eller .create(cwd, mappe, { id }) */,
});
```

`noTools: 'builtin'` tar bort bash/read/write/edit; politikken stoler likevel ikke på
det og har sin egen liste. `SessionManager` gir lagring som JSONL melding for melding
og komprimering når tråden blir lang — begge deler du ellers hadde skrevet selv.
`ModelRuntime.create({ credentials })` med en egen `CredentialStore` holder tokenet i
appens datamappe, ikke i `~/.pi`.

**Test politikken med faux-modellen** (punkt 6) — `modelRuntime.registerNativeProvider(faux.provider)`
og la modellen «be om» sletting etter «rydd opp»: assert `isError` og at oppføringen
står. Så det samme etter «slett»: assert at den er borte. Og test at et verktøy som
ikke finnes (`bash`) blokkeres, og at journalen får én linje per gjennomført endring
og null for lesing og feil.

## Sjekkliste

- [ ] Verktøyene skriver gjennom appens HTTP-API, ikke i lagringen
- [ ] `label` på norsk (eller brukerens språk), og den strømmes mens verktøyet kjører
- [ ] `execute` kaster ved feil; serverens `{ feil }` blir feilmeldingen
- [ ] Hvert skriveresultat har et ferdig `sammendrag` med de identifiserende feltene
- [ ] Endring returnerer forrige verdi; sletting returnerer det slettede objektet
- [ ] Sletting slår opp oppføringen først
- [ ] Grenseverdier avvises i kode, med grensen i feilmeldingen
- [ ] Systemprompten har de seks reglene, og sier at de går foran
- [ ] Tester mot faux-provider + ekte server, med assert på disk og på `isError`
- [ ] Utvalget av verktøy er begrunnet i en kommentar, ikke bare arvet fra API-et
- [ ] Politikken er en `tool_call`-utvidelse: liste over tillatte verktøy, sletting
      bare på brukerens egne ord, journal over gjennomførte endringer
- [ ] Sesjonen laster ingenting fra `~/.pi` (`noExtensions`, `noSkills`, …) og har
      `noTools: 'builtin'`
