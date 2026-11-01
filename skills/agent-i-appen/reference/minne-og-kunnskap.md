# Minne, kunnskapsgraf og bakgrunnsagenter

Når agenten skal huske ting mellom samtaler, bygge opp det den vet om brukernes verden
(en kunnskapsgraf eller LLM-wiki), lese inn dokumenter, eller jobbe i bakgrunnen uten noen
til stede. Fra en husholdningsapp med Pi-agent; de fleste punktene ble funnet gjennom feil
og sikkerhetsgjennomganger. Skrivingen selv følger skriveverktoy.md, og tekst utenfra
følger fremmed-tekst.md.

## 1. Minne som står i hver samtale

Det agenten «husker» (allergier, vaner, ønsker) legges inn i konteksten før hver tur, for
alle brukerne. Det er den farligste skrivingen i appen: én innsmuglet setning fra en
e-post eller en nettside blir en fast instruks i hver samtale. Derfor gjelder dette i
koden, ikke bare i prompten:

- **Teksten må være brukerens.** To veier slipper gjennom, ingen andre:
  1. En oppfordring i en av de to siste meldingene, og det meste av teksten som lagres
     står i den meldingen (vi bruker minst 60 % av innholdsordene, tre bokstaver og mer).
  2. Den nyeste meldingen er et klart ja (uten forbehold), og agentens forrige svar
     inneholdt «huske at <nøyaktig teksten>».
- **Et utløserord alene er ikke nok.** `husk` i ordlista slipper «husker du hva …?»
  gjennom, og da kan hvilken som helst tekst lagres. Bruk oppfordringer
  (`husk`, `ikke glem`, `noter deg`, `kan du huske`), ikke `husker`/`huske`.
- **Vakten trenger agentens siste svar** før brukerens melding. Gi vaktene det som et
  generelt felt i samtaleutsnittet, ikke som noe én vakt graver fram selv.
- **I hver samtale står bare godkjent tekst og tall.** Aldri navn, aliaser eller
  beskrivelser agenten har laget selv: de kan komme fra fremmed tekst. La minnet være hele
  setninger med navnet i («X er allergisk mot nøtter»), så teksten står alene.
- Sett et tak på hvor mye som legges inn (vi bruker 3000 tegn), og vis resten som «… og N til».

## 2. Kunnskapsgraf og innlesing (LLM-wiki)

En kunnskapsgraf er noder (personer, ting, firmaer, steder, temaer) med fakta, og
koblinger med en kort relasjon. Det er det samme som en LLM-wiki med tre operasjoner:
inn (innhenting og innlesing), spør (søk og hent) og rydd (se punkt 3).

- **To slags skriving, to regler.** Grafen fyller agenten selv mens dere snakker, uten
  utløserord: når noe varig blir sagt, lagrer den og sier det («La inn i kunnskapen: …»).
  Grafen leses bare når agenten søker, så vakten fra punkt 1 gjelder ikke her. Krever du
  «husk» for grafen også, blir den aldri fylt. Det som allerede finnes i appen (oppgaver,
  tilbud), kobles med ref og kopieres ikke inn. Følg med i journalen på om agenten faktisk
  lagrer av seg selv; det ser du først ved ekte bruk.
- **`ref` binder grafen til appen.** En node kan være et objekt som finnes fra før
  (`rom:<id>`, `side:<id>`); navnet hentes fra modulen ved lesing. Da speiler grafen appen
  i stedet for å kopiere den.
- **Én lagring i én omgang, med gjenbruk.** Noder, fakta og koblinger i ett kall og én
  transaksjon. Finn eksisterende node på ref, så på navn og type, så på navn eller alias
  uansett type. Uten det siste får du to av alt («Elkjøp» som firma og som sted).
- **Skjelettet først, uten modell.** Bygg nodene og koblingene appen allerede vet
  (rom i huset, sider under kategori, ting under rom) med kode. Kjør det trygt flere ganger.
- **Innlesing med modell, én kilde om gangen:**
  - Bare kilder som er nye eller endret siden sist (lagre versjonen som er lest).
  - Kilden (`kilde: «Side: <tittel>»`) settes av koden, aldri av modellen.
  - Gi modellen de kjente nodene den skal bruke (rommene med id). Ellers lager den «Kjøkkenet i …» ved siden av «Kjøkken».
  - Søk-først-regel, tak per kilde, og samme lagringsfunksjon som agenten bruker.
- **Et sammendrag per node er wikisiden.** Modellen skriver noen setninger bare fra
  fakta og koblinger. Skriv på nytt når noden endrer seg.
  - **Ta bort teksten når noe den bygger på slettes:** et faktum, en kobling, en nabo, eller
    en sammenslåing. Sletting endrer ingen tidsstempler, så uten dette står det slettede igjen.
- **Nummersperren** (konto-, kort- og fødselsnumre) ble omgått fire ganger før den holdt:
  - Fjern skilletegn mellom sifre og nullbreddetegn.
  - Sjekk hver sammenhengende rekke av sifergrupper (11 eller 13–19 sifre), ikke bare
    lengden på hele løpet: «1234.56.78901 2» er 12 sifre.
  - Slipp bare *gyldige* datoer: «1234-56-78 901» er ikke en dato.
  - Gjør det i *alle* tekstfelt: navn, alias, beskrivelse, relasjon, notat, kilde og
    begrunnelsen i et forslag.

## 3. Bakgrunnsagenter: uten bruker til stede

En jevnlig runde (rydde grafen, skrive sammendrag) er en egen agentsesjon uten noen som
kan si ja.

- **Samme prosess og samme kjøretid** som samtalene. To prosesser som fornyer samme
  OAuth-token, slår hverandre ut.
- **Ikke gjenbruk samtalepolitikken.** Der er brukerens ord fullmakten. Her er
  «brukermeldingen» rundens egen prompt, så et sletteord i den ville gitt fullmakt. Gi
  runden en egen hvitliste og tak på kall og tokens (tell `usage` i `message_end`). Slå av
  komprimering og cache-oppvarming, og tillat ett nytt forsøk.
- **Foreslå, ikke endre.** Runden lager forslag som et menneske godtar eller avviser i
  appen.
  - Et avvist forslag foreslås ikke igjen. Bruk en nøkkel per forslag.
  - Et forslag om noe som er borte, blir utdatert.
  - Sjekk forslaget mot dataene både når det lages og når det utføres.
- **Kode før modell.** Døde ref-er, tomme noder og like navn finner koden selv. Modellen
  får bare det koden ikke ser: dubletter med ulike navn, motsigelser og utdaterte fakta.
- **Når:** sjelden (ukentlig holder for en husholdning), om natta, ikke når noen har brukt
  appen de siste minuttene, og bare når noe er endret siden sist. Ikke rull ut midt i en
  runde: en avbrutt runde teller som ukens.
- **Modell:** en billigere rutinemodell som én konstant. Bruk den dyre modellen bare for et
  engangsløft.

## Sjekkliste

- [ ] Minne i hver samtale: brukerens egne ord eller ja til nøyaktig tekst, håndhevet i en
      vakt; bare godkjent tekst og tall i konteksten
- [ ] Grafen fylles uten utløserord; det som finnes i appen, kobles med ref
- [ ] Gjenbruk på navn og alias på tvers av type; kilden satt av koden; kjente noder til
      innleseren
- [ ] Nummersperren normalisert, med gyldige datoer og hver rekke av sifre, i alle felt
- [ ] Avledet tekst (sammendrag) tas bort når det den bygger på slettes
- [ ] Bakgrunnsagent: samme kjøretid, egen hvitliste og tak, bare forslag, avvist kommer
      ikke igjen, ikke rull ut midt i en runde
