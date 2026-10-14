# Sesjon, kontekst og drift av agenten

Det som gjorde reiseapp til noe mer enn en nettside: en Pi-agent
(pi-coding-agent) på serveren, med Claude Max-innlogging, verktøy som speiler det brukerne
selv kan endre, og en skrivepolitikk i kode. Referanse: `reiseapp/agent/`.

## Sesjon og lagring

- **Én levende sesjon per samtale på serveren**, `AgentSession` fra pi-coding-agent, ikke
  en rå `Agent`: da eier Pi tråden, køen (`followUp()`), «ett svar om gangen», lagringen
  (JSONL per samtale under `<data>/samtaler/`) og komprimeringen. Nettleseren er en tynn
  tegner (se `pwa`-skillen, reference/chat-og-stromming.md).
- `DefaultResourceLoader` med `noExtensions/noSkills/noPromptTemplates/noThemes/noContextFiles`
  og `additionalExtensionPaths` til `node_modules/<pakke>`: ingenting fra `~/.pi` — alt
  agenten kan, står i repoet. Sjekk `loader.getExtensions().errors` og kast.
- Under en herdet systemd-tjeneste må Pi pekes vekk fra hjemmemappa:
  `PI_CODING_AGENT_DIR=<data>/pi-agent`, `PI_MEMORY_DIR=<data>/agent-minne`,
  `PI_MEMORY_EXIT_SUMMARY=0` (ellers koster hver disponert sesjon et modellkall).
- `ModelRuntime.create({ modelsPath: null, allowModelNetwork: false })`: en utrulling skal
  ikke avhenge av en katalogtjeneste. Én kjøretid per prosess — to ville fornye tokenet
  samtidig og slå hverandre ut. Modellen kan velges per bruker: lagre valget i appens
  datamappe og gi sesjonsbyggeren modellen som parameter, så kan en tråd fortsette
  på en annen modell enn den startet med.
- **Ikke `fetch` mot egen server fra agentprosessen.** Pi bytter ut den globale
  dispatcheren når den lastes, og kall til localhost tok 1–2 s mot 2 ms med
  `node:http`. Se skriveverktoy.md punkt 1.
- OAuth-tokenet i `<data>/pi-auth.json` (0600, gitignored), skrevet atomisk, med en
  løftekjede som lås rundt `modify`. `getAuth('anthropic')` svarer `{ auth, source }` —
  nøkkelen ligger ett nivå ned; leste man ytterste nivå «virket søket aldri».
- Innlogging uten terminal: når `!process.stdin.isTTY`, skriv auth-URL-en til en fil og
  vent på koden i en annen (slett begge i `finally`).
- **Max-OAuth mot Anthropic-SDK-en gir 429 med mindre forespørselen ser ut som Claude
  Code** — det er en avvisning, ikke kvote: `new Anthropic({ apiKey: null, authToken })`,
  headere `user-agent: claude-cli/<versjon>`, `x-app: cli`,
  `betas: ['claude-code-20250219', 'oauth-2025-04-20']`, første system-blokk =
  Claude Code-identiteten, `web_search_20250305` med `max_uses`; søk telles i
  `usage.server_tool_use.web_search_requests`. Én felles hjelper for prosa- og JSON-svar.

## Kontekst og kostnad

- `context`-utvidelse trimmer det som **sendes**, ikke det som lagres: verktøyresultater
  fra tidligere runder byttes med et merke (`hent_turen` er ~50 KB per runde), men
  `toolCallId`/`toolName` beholdes så paringen holder. Bilder bare i de to siste
  brukermeldingene.
- Systemprompten lages én gang per sesjon, og en sesjon kan leve i dagevis. Fersk
  tilstand (dato og klokke i brukernes sone, og et kort utdrag av det appen viser nå)
  legges inn med en `before_agent_start`-krok, som kjører før hver tur og returnerer
  `{ systemPrompt: h.systemPrompt + '\n\nSlik står det til nå: …' }`. Hent med
  tidsavbrudd og en kort cache, og la en del som feiler bare bli borte.
- Det agenten får av data slankes bevisst: bildelister ut, men ett bilde per sted (så den
  kan vise det), vedlegg som `{ navn, url }` (så den kan lese billetten).
- Bilder til modellen skaleres på serveren til 1568 px lengste side, JPEG 80, `.rotate()`
  for EXIF — modellen skalerer uansett ned; større koster bare tokens, og rare formater gir
  400 `image.source`.

## Verktøy og politikk

- Verktøyene speiler det brukerne selv kan endre i appen, ikke mer; hvert skrivende
  verktøy svarer med en ferdig setning agenten skal gjengi («Skrev dagboka for …»).
- **Skrivepolitikk som Pi-utvidelse på `tool_call`**, ikke bare i prompten: hvitliste av
  navn; sletteverktøy krever et sletteord (`slett|fjern|ta bort|stryk|dropp`) i en av de
  *to* siste brukermeldingene; dyre verktøy (`krever`) krever et utløserord; `tool_result`
  journalføres som JSON-linjer i `<data>/agent-endringer.jsonl`, og en `/endringer`-kommando
  viser de siste. Se skriveverktoy.md punkt 7.
- Delvis PUT for data flere skriver til: bare felt som *finnes* i kroppen erstattes, og
  verktøybeskrivelsen sier det samme («Bare feltene du sender endres»).
- Skråstrek-kommandoer eies av serveren og utvides til hele setninger; systemkommandoer
  (`/nytt`, `/stopp`) når aldri modellen — før svarte modellen «Samtalen er tømt» uten at
  noe skjedde. Aliaser for vanen fra Claude/ChatGPT (`/clear`, `/stop`).
- Appen kan bestille selv (morgenmelding, kveldsskriving): merket `[app]` i teksten,
  vist som en linje, ikke som en boble; tre tilstander per dag så en omstart ikke
  bestiller to (`pwa`-skillen, reference/push-varsler.md).
- JSON fra et søkeverktøy: «svar BARE med JSON», trekk ut første `{…}`, fall tilbake til
  `{ raa, usikker: true }` — men **logg fallbacket**. **Felle:** en hjelper som byttet fra
  streng til `{ tekst, sok }` lot en kaller gjøre `svar.replace` på objektet; det kastet
  inni `try`, og hver kryssjekk var «usikker» i dagevis uten at noen så det. Verktøy som
  «alltid er usikre» er et symptom, ikke et modellproblem.
- Systemprompt som skal få agenten til å lage en hel side virker best som en nummerert
  oppskrift (hent data → søk → les PDF → kryssjekk → skriv), med hvilke verktøy hvert steg
  bruker, og knapper som lenker til app-ruter (`#/vaer/<dato>`).
- PDF-lesing: sjekk `%PDF`-magien, `pdfinfo` for sidetall, `pdftotext -layout` (kolonnene
  overlever — markdown-konvertering gjør det ikke), `pdftoppm -r 110` som bilde når
  tabellen er for tett; `mkdtemp` + `rmSync` i `finally`, `signal` til `execFile`.
- Appens egne filer hentes over `basisUrl` med fast regex på sti, aldri gjennom
  SSRF-vakten (som ellers nekter appens egen adresse) og aldri `/api/`.
- Tolerant tekstmatch mot egne data: `toLowerCase().normalize('NFD')`, strip kombinerende
  tegn, alt utenom `a-z0-9æøå` til mellomrom, alias-liste per sted, typeport.

## Testing

Agentloopen mot Pi sin faux-provider (ingen nettverk), **gjennom samme samtale-modul som
drift bruker** — testene på `agent.prompt()` så aldri kø-, id- og opptatt-feilene. Assert
rekkefølge og antall hendelser (`['user','assistant','user','assistant']`, én `ferdig`,
`koet.id === andre.id`).
