// Ende til ende: appen står oppe med service worker, en ny versjon rulles ut, og
// sida skal bytte av seg selv ved forgrunn — og vise «Hent den» under bruk.
// Bruk: node nyversjon-e2e.mjs <appmappe> <datamappe> [port]
// <appmappe> er en kopi av appen (skriptet skriver i den), <datamappe> en tom datamappe.
// Tilpass MILJO, stiene til index.html og sw.js, og velgerne i tilstand() til appen.
//
// Skriptet eier alt det starter — serveren, Chrome og profilmappa — og rydder det i
// rydd(), som kjøres i finally og ved Ctrl-C/SIGTERM. Ingen venting er uten frist.
import { spawn } from 'node:child_process'; import fs from 'node:fs'; import os from 'node:os'; import path from 'node:path';
import { finnChrome } from './chrome.mjs';
const [D, T, PORT = '3404'] = process.argv.slice(2);
if (!D || !T) { console.error('bruk: node nyversjon-e2e.mjs <appmappe> <datamappe> [port]'); process.exit(1); }
const BASIS = `http://127.0.0.1:${PORT}`;
const MILJO = { PORT, APP_DATA: T, APP_INGEN_VARSLER: '1' };   // appens egne variabler
const vent = (ms) => new Promise((r) => setTimeout(r, ms));
// Fristene holder ikke prosessen i live når jobben er ferdig: timeren ryddes eller unref-es.
const medFrist = (p, ms, hva) => {
  let t;
  const frist = new Promise((_, feil) => { t = setTimeout(() => feil(new Error(`${hva}: ingen svar på ${ms} ms`)), ms); });
  return Promise.race([p, frist]).finally(() => clearTimeout(t));
};
const ventInntil = (p, ms) => Promise.race([p, new Promise((r) => setTimeout(r, ms).unref())]);

// Versjonen serveren svarer med, eller undefined når ingen svarer. Fristen gjelder både
// headere og kropp (signalet avbryter også lesingen av JSON-en).
const versjonNaa = async () => {
  try {
    const svar = await fetch(BASIS + '/api/versjon', { signal: AbortSignal.timeout(2000) });
    return (await svar.json()).versjon ?? null;
  } catch { return undefined; }
};

// En barneprosess med et løfte som innfris når den er borte — også når den ble drept med
// signal (exitCode er da null) eller aldri startet ('error').
function startProsess(fil, args, valg) {
  const barn = spawn(fil, args, valg);
  let borte = false; let feil = null;
  const ferdig = new Promise((r) => {
    barn.once('exit', () => { borte = true; r(); });
    barn.once('error', (f) => { feil = f; borte = true; r(); });
  });
  return { barn, ferdig, borte: () => borte, feil: () => feil };
}
async function stopp(p, ms = 5000) {
  if (!p || p.borte()) return;
  p.barn.kill();
  await ventInntil(p.ferdig, ms);
  if (!p.borte()) { p.barn.kill('SIGKILL'); await p.ferdig; }
}

// Serveren: én prosess startes før første navigering og startes på nytt ved hver utrulling.
let server = null;
async function startServer(versjon) {
  server = startProsess(process.execPath, ['server.js'], { cwd: D, env: { ...process.env, ...MILJO }, stdio: 'ignore' });
  for (let i = 0; i < 40 && !server.borte(); i++) {
    const v = await versjonNaa();
    if (v !== undefined && (versjon === undefined || v === versjon)) return;
    await vent(250);
  }
  const grunn = server.feil()?.message ?? (server.borte() ? `avsluttet (kode ${server.barn.exitCode ?? server.barn.signalCode})` : 'svarte ikke');
  await stopp(server); server = null;
  throw new Error(`serveren i ${D} på ${BASIS}: ${grunn}`);
}
async function stoppServer() { await stopp(server); server = null; }

async function rullUt(versjon, cache) {
  // «Ny utrulling»: ny versjonsstreng i versjon.txt og index.html, nytt cachenavn i sw.js, og omstart.
  fs.writeFileSync(path.join(D, 'versjon.txt'), versjon + '\n');
  const ix = path.join(D, 'public/index.html');
  fs.writeFileSync(ix, fs.readFileSync(ix, 'utf8').replace(/name="versjon" content="[^"]*"/, `name="versjon" content="${versjon}"`));
  const sw = path.join(D, 'public/sw.js');
  fs.writeFileSync(sw, fs.readFileSync(sw, 'utf8').replace(/const CACHE = '[^']*'/, `const CACHE = '${cache}'`));
  await stoppServer();
  await startServer(versjon);
}

// Det som kan feile uten å ha startet noe, sjekkes først.
const CHROME = finnChrome();
if ((await versjonNaa()) !== undefined) { console.error(`noe svarer alt på ${BASIS}; stopp det eller velg en annen port`); process.exit(1); }

const DEV = 9200 + Math.floor(Math.random() * 60);
const profil = fs.mkdtempSync(path.join(os.tmpdir(), 'chrome-nv-'));
let chrome = null, ws = null, ryddet = null;
const rydd = () => (ryddet ??= (async () => {
  try { ws?.close(); } catch {}
  await stopp(chrome);
  await stoppServer();
  try { fs.rmSync(profil, { recursive: true, force: true }); } catch {}
})());
for (const s of ['SIGINT', 'SIGTERM']) process.once(s, () => { rydd().finally(() => process.exit(130)); });

try {
  await startServer();
  chrome = startProsess(CHROME, ['--headless=new', '--disable-gpu', '--disable-extensions', '--no-sandbox', `--remote-debugging-port=${DEV}`, `--user-data-dir=${profil}`, 'about:blank'], { stdio: 'ignore' });
  let side;
  for (let i = 0; i < 50 && !side && !chrome.borte(); i++) {
    try { side = (await (await fetch(`http://127.0.0.1:${DEV}/json/list`, { signal: AbortSignal.timeout(2000) })).json()).find((t) => t.type === 'page'); } catch {}
    if (!side) await vent(200);
  }
  if (!side) throw new Error(`Chrome (${CHROME}) ${chrome.feil()?.message ?? (chrome.borte() ? 'avsluttet' : 'svarte ikke på CDP')}`);
  ws = new WebSocket(side.webSocketDebuggerUrl);
  await medFrist(new Promise((ok, feil) => { ws.onopen = ok; ws.onerror = () => feil(new Error('WebSocket mot Chrome feilet')); }), 10000, 'WebSocket mot Chrome');

  let id = 0; const venter = new Map(); let lastinger = 0; const unntak = [];
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (m.method === 'Page.frameNavigated' && !m.params.frame.parentId && m.params.frame.url.startsWith(BASIS)) lastinger++;
    if (m.method === 'Runtime.exceptionThrown') unntak.push((m.params.exceptionDetails.exception?.description || '').slice(0, 120));
    if (m.id && venter.has(m.id)) { venter.get(m.id)(m); venter.delete(m.id); }
  };
  ws.onclose = () => { for (const r of venter.values()) r({ error: { message: 'Chrome lukket forbindelsen' } }); venter.clear(); };
  const kall = (metode, params = {}) => medFrist(new Promise((r) => {
    const i = ++id; venter.set(i, r); ws.send(JSON.stringify({ id: i, method: metode, params }));
  }), 30000, metode);
  const ev = async (x) => (await kall('Runtime.evaluate', { expression: x, returnByValue: true, awaitPromise: true })).result?.result?.value;

  await kall('Page.enable'); await kall('Runtime.enable');
  await kall('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: true });
  const tilstand = async () => ({
    meta: await ev("document.querySelector('meta[name=versjon]')?.content"),
    sw: await ev("fetch('/sw-versjon').then(r=>r.ok?r.text():null).catch(()=>null)"),
    fot: await ev("document.querySelector('.appfot')?.textContent"),
    varsel: await ev("document.querySelector('.varsel')?.textContent||null"),
  });
  const ut = {};
  // 1. Første lasting med service worker (uten bypass), til en rute der appfoten står
  await kall('Page.navigate', { url: BASIS + '/#/praktisk' }); await vent(6000);
  ut.start = await tilstand();
  // 2. Ny utrulling; appen «kommer i forgrunnen» → skal laste seg selv på nytt
  await rullUt('v2test · 2026-09-15', 'app-v99');
  lastinger = 0;
  await ev("Object.defineProperty(document,'visibilityState',{value:'visible',configurable:true}); document.dispatchEvent(new Event('visibilitychange'))");
  let etter; for (let i = 0; i < 60; i++) { await vent(500); etter = await tilstand(); if (etter.meta?.startsWith('v2test')) break; }
  ut.etterForgrunn = { ...etter, lastinger };
  // 3. Enda en utrulling; oppdaget under bruk (sjekken uten auto) → melding, ingen omlasting
  await rullUt('v3test · 2026-09-16', 'app-v100');
  lastinger = 0;
  await ev("import('/app.js').then(m=>m.sjekkVersjon({auto:false}))"); await vent(1500);
  ut.underBruk = { ...(await tilstand()), lastinger };
  // 4. Trykk «Hent den» → ny versjon
  await ev("[...document.querySelectorAll('.varsel button')].find(b=>b.textContent==='Hent den')?.click()");
  let etter2; for (let i = 0; i < 60; i++) { await vent(500); etter2 = await tilstand(); if (etter2.meta?.startsWith('v3test')) break; }
  ut.etterHentDen = { ...etter2, lastinger };
  ut.unntak = unntak.slice(0, 3);
  console.log(JSON.stringify(ut, null, 1));
} finally {
  await rydd();
}
