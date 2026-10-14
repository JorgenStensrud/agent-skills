// Ende til ende: appen står oppe med service worker, en ny versjon rulles ut, og
// sida skal bytte av seg selv ved forgrunn — og vise «Hent den» under bruk.
// Bruk: node nyversjon-e2e.mjs <appmappe> <datamappe> [port]
// <appmappe> er en kopi av appen (skriptet skriver i den), <datamappe> en tom datamappe.
// Tilpass MILJO, stiene til index.html og sw.js, og velgerne i tilstand() til appen.
import { spawn } from 'node:child_process'; import fs from 'node:fs'; import os from 'node:os'; import path from 'node:path';
import { finnChrome } from './chrome.mjs';
const [D, T, PORT = '3404'] = process.argv.slice(2);
if (!D || !T) { console.error('bruk: node nyversjon-e2e.mjs <appmappe> <datamappe> [port]'); process.exit(1); }
const BASIS = `http://127.0.0.1:${PORT}`;
const MILJO = { PORT, APP_DATA: T, APP_INGEN_VARSLER: '1' };   // appens egne variabler
const vent = (ms) => new Promise((r) => setTimeout(r, ms));
const versjonNaa = async () => { try { return (await (await fetch(BASIS + '/api/versjon')).json()).versjon ?? null; } catch { return undefined; } };
// Skriptet eier serveren: én prosess startes før første navigering og startes på nytt
// ved hver utrulling. Svarer noe alt på porten, er det en annen server, og da stopper vi.
let server;
async function startServer(versjon) {
  server = spawn(process.execPath, ['server.js'], { cwd: D, env: { ...process.env, ...MILJO }, stdio: 'ignore' });
  const ferdig = new Promise((r) => server.once('exit', r));
  for (let i = 0; i < 40; i++) {
    const v = await versjonNaa();
    if (v !== undefined && (versjon === undefined || v === versjon)) return;
    if (server.exitCode !== null) break;
    await vent(250);
  }
  server.kill(); await ferdig;
  throw new Error(`serveren i ${D} svarte ikke på ${BASIS}/api/versjon`);
}
async function stoppServer() {
  if (!server || server.exitCode !== null) return;
  const ferdig = new Promise((r) => server.once('exit', r));
  server.kill(); await ferdig;
}
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
// Chrome finnes før serveren startes, og alt skriptet starter, ryddes i finally:
// ellers blir serveren hengende og holder porten når noe feiler underveis.
const CHROME = finnChrome();
if ((await versjonNaa()) !== undefined) { console.error(`noe svarer alt på ${BASIS}; stopp det eller velg en annen port`); process.exit(1); }
const DEV = 9200 + Math.floor(Math.random()*60);
const profil = fs.mkdtempSync(path.join(os.tmpdir(),'chrome-nv-'));
let chrome, ws;
try {
await startServer();
chrome = spawn(CHROME,['--headless=new','--disable-gpu','--disable-extensions','--no-sandbox',`--remote-debugging-port=${DEV}`,`--user-data-dir=${profil}`,'about:blank'],{stdio:'ignore'});
let liste; for(let i=0;i<50;i++){try{liste=await (await fetch(`http://127.0.0.1:${DEV}/json/list`)).json();if(liste.length)break;}catch{}await vent(200);}
ws=new WebSocket(liste.find(t=>t.type==='page').webSocketDebuggerUrl); await new Promise(r=>(ws.onopen=r));
let id=0; const v=new Map(); let lastinger=0; const feil=[];
ws.onmessage=(e)=>{const m=JSON.parse(e.data); if(m.method==='Page.frameNavigated'&&!m.params.frame.parentId&&m.params.frame.url.startsWith(BASIS)) lastinger++; if(m.method==='Runtime.exceptionThrown') feil.push((m.params.exceptionDetails.exception?.description||'').slice(0,120)); if(m.id&&v.has(m.id)){v.get(m.id)(m);v.delete(m.id);}};
const kall=(me,p={})=>new Promise(r=>{const i=++id;v.set(i,r);ws.send(JSON.stringify({id:i,method:me,params:p}));});
const ev=async(x)=>(await kall('Runtime.evaluate',{expression:x,returnByValue:true,awaitPromise:true})).result?.result?.value;
await kall('Page.enable'); await kall('Runtime.enable');
await kall('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
const tilstand = async () => ({ meta: await ev("document.querySelector('meta[name=versjon]').content"), sw: await ev("fetch('/sw-versjon').then(r=>r.ok?r.text():null).catch(()=>null)"), fot: await ev("document.querySelector('.appfot')?.textContent"), varsel: await ev("document.querySelector('.varsel')?.textContent||null") });
const ut = {};
// 1. Første lasting med service worker (uten bypass), til Praktisk så appfoten står
await kall('Page.navigate',{url:BASIS+'/#/praktisk'}); await vent(6000);
ut.start = await tilstand();
// 2. Ny utrulling; appen «kommer i forgrunnen» → skal laste seg selv på nytt
await rullUt('v2test · 2026-09-15', 'app-v99');
lastinger = 0;
await ev("Object.defineProperty(document,'visibilityState',{value:'visible',configurable:true}); document.dispatchEvent(new Event('visibilitychange'))");
let etter; for (let i=0;i<60;i++){ await vent(500); etter = await tilstand(); if (etter.meta?.startsWith('v2test')) break; }
ut.etterForgrunn = { ...etter, lastinger };
// 3. Enda en utrulling; oppdaget under bruk (sjekken uten auto) → melding, ingen omlasting
await rullUt('v3test · 2026-09-16', 'app-v100');
lastinger = 0;
await ev("import('/app.js').then(m=>m.sjekkVersjon({auto:false}))"); await vent(1500);
ut.underBruk = { ...(await tilstand()), lastinger };
// 4. Trykk «Hent den» → ny versjon
await ev("[...document.querySelectorAll('.varsel button')].find(b=>b.textContent==='Hent den')?.click()");
let etter2; for (let i=0;i<60;i++){ await vent(500); etter2 = await tilstand(); if (etter2.meta?.startsWith('v3test')) break; }
ut.etterHentDen = { ...etter2, lastinger };
ut.unntak = feil.slice(0,3);
console.log(JSON.stringify(ut,null,1));
} finally {
  ws?.close(); chrome?.kill(); await stoppServer(); try{fs.rmSync(profil,{recursive:true,force:true});}catch{}
}
