// Går gjennom ruter med service worker PÅ og samler konsollfeil, HTTP ≥ 400 og bilder
// som ikke lastet. Kjør mot produksjon etter utrulling (bare lesing).
//   node konsoll.mjs http://127.0.0.1:3210 '' program utforsk praktisk
import { spawn } from 'node:child_process'; import fs from 'node:fs'; import os from 'node:os'; import path from 'node:path';
const [basis = 'http://127.0.0.1:3210', ...RUTER] = process.argv.slice(2);
const DEV = 9850 + Math.floor(Math.random() * 60);
const profil = fs.mkdtempSync(path.join(os.tmpdir(), 'chrome-k-'));
const chrome = spawn(process.env.CHROME || '/usr/bin/google-chrome', ['--headless=new', '--disable-gpu', '--disable-extensions', '--no-sandbox', `--remote-debugging-port=${DEV}`, `--user-data-dir=${profil}`, 'about:blank'], { stdio: 'ignore' });
let liste; for (let i = 0; i < 50; i++) { try { liste = await (await fetch(`http://127.0.0.1:${DEV}/json/list`)).json(); if (liste.length) break; } catch {} await new Promise((r) => setTimeout(r, 200)); }
const ws = new WebSocket(liste.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
let id = 0; const v = new Map(); const funn = []; let rute = '';
ws.onmessage = (e) => { const m = JSON.parse(e.data);
  if (m.method === 'Runtime.consoleAPICalled' && ['error', 'warning'].includes(m.params.type)) funn.push(`${rute} konsoll: ${m.params.args.map((a) => a.value || a.description || '').join(' ').slice(0, 120)}`);
  if (m.method === 'Runtime.exceptionThrown') funn.push(`${rute} unntak: ${(m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text).slice(0, 150)}`);
  if (m.method === 'Network.responseReceived' && m.params.response.status >= 400) funn.push(`${rute} HTTP ${m.params.response.status}: ${m.params.response.url.slice(0, 90)}`);
  if (m.id && v.has(m.id)) { v.get(m.id)(m); v.delete(m.id); } };
const kall = (me, p = {}) => new Promise((r) => { const i = ++id; v.set(i, r); ws.send(JSON.stringify({ id: i, method: me, params: p })); });
const ev = async (x) => (await kall('Runtime.evaluate', { expression: x, returnByValue: true, awaitPromise: true })).result?.result?.value;
await kall('Network.enable'); await kall('Page.enable'); await kall('Runtime.enable');
await kall('Page.navigate', { url: basis + '/' }); await new Promise((r) => setTimeout(r, 4000));
await kall('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: true });
for (const r of RUTER) {
  rute = r || 'hjem';
  await kall('Page.navigate', { url: 'about:blank' }); await new Promise((x) => setTimeout(x, 200));
  await kall('Page.navigate', { url: basis + '/#/' + r }); await new Promise((x) => setTimeout(x, 2600));
  const brutte = await ev('[...document.images].filter(i=>i.complete&&i.naturalWidth===0).map(i=>i.src.slice(-50))');
  if (brutte?.length) funn.push(`${rute} bilder som ikke lastet: ${brutte.slice(0, 3).join(', ')}`);
}
console.log([...new Set(funn)].join('\n') || 'ingen feil funnet');
ws.close(); chrome.kill(); try { fs.rmSync(profil, { recursive: true, force: true }); } catch {}
