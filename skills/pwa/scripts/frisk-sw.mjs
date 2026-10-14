// Fersk installasjon MED service worker: installerer skallet uten feil, og laster de
// late rutene? Kjør etter hver utrulling som endrer sw.js eller skallet.
//   node frisk-sw.mjs http://127.0.0.1:3210 app-v67 '#/utforsk' '#/program'
import { spawn } from 'node:child_process'; import fs from 'node:fs'; import os from 'node:os'; import path from 'node:path';
import { finnChrome } from './chrome.mjs';
const [basis = 'http://127.0.0.1:3210', cacheNavn, ...ruter] = process.argv.slice(2);
const DEV = 9500 + Math.floor(Math.random() * 80);
const profil = fs.mkdtempSync(path.join(os.tmpdir(), 'chrome-frisk-'));
const chrome = spawn(finnChrome(), ['--headless=new', '--disable-gpu', '--disable-extensions', '--no-sandbox', `--remote-debugging-port=${DEV}`, `--user-data-dir=${profil}`, 'about:blank'], { stdio: 'ignore' });
let liste; for (let i = 0; i < 50; i++) { try { liste = await (await fetch(`http://127.0.0.1:${DEV}/json/list`)).json(); if (liste.length) break; } catch {} await new Promise((r) => setTimeout(r, 200)); }
const ws = new WebSocket(liste.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
let id = 0; const v = new Map(); const feil = [];
ws.onmessage = (e) => { const m = JSON.parse(e.data);
  if (m.method === 'Runtime.consoleAPICalled' && m.params.type === 'error') feil.push(m.params.args.map((a) => a.value || a.description).join(' '));
  if (m.method === 'Runtime.exceptionThrown') feil.push('unntak: ' + (m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text));
  if (m.method === 'Network.loadingFailed') feil.push('lasting feilet: ' + m.params.errorText);
  if (m.id && v.has(m.id)) { v.get(m.id)(m); v.delete(m.id); } };
const kall = (method, params = {}) => new Promise((r) => { const i = ++id; v.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (x) => (await kall('Runtime.evaluate', { expression: x, returnByValue: true, awaitPromise: true })).result?.result?.value;
await kall('Network.enable'); await kall('Page.enable'); await kall('Runtime.enable');
await kall('Page.navigate', { url: basis + '/' }); await new Promise((r) => setTimeout(r, 6000));
const sw = await ev("navigator.serviceWorker.getRegistration().then(r=>r? (r.active?'aktiv':'installerer') : 'ingen')");
const cache = await ev('caches.keys().then(k=>k.join(","))');
const antall = cacheNavn ? await ev(`caches.open('${cacheNavn}').then(c=>c.keys()).then(k=>k.length)`) : null;
for (const h of ruter) { await kall('Page.navigate', { url: basis + '/' + h }); await new Promise((r) => setTimeout(r, 1800)); }
const tittel = await ev("document.querySelector('main h1')?.textContent");
console.log(JSON.stringify({ sw, cache, iSkall: antall, sisteTittel: tittel, feil: [...new Set(feil)].slice(0, 6) }, null, 1));
ws.close(); chrome.kill(); try { fs.rmSync(profil, { recursive: true, force: true }); } catch {}
