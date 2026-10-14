// Skjermbilde av én rute i 390 px mobilmodus, utenom service workeren, med valgfri JS
// som kjøres før bildet tas (resultatet skrives ut). Bruk:
//   node skjerm.mjs 'http://127.0.0.1:3210/#/program' /tmp/program.png "document.title"
// --init <js> kjøres før sidas egen kode (sett localStorage før første tegning);
// --mork tar bildet i mørk modus.
import { spawn } from 'node:child_process'; import fs from 'node:fs'; import os from 'node:os'; import path from 'node:path';
import { finnChrome } from './chrome.mjs';
const flagg = {}; const pos = []; const arg = process.argv.slice(2);
for (let i = 0; i < arg.length; i++) {
  if (arg[i] === '--init') flagg.init = arg[++i];
  else if (arg[i] === '--mork') flagg.mork = true;
  else pos.push(arg[i]);
}
const [url, ut, js] = pos;
if (!url || !ut) { console.error('bruk: node skjerm.mjs <url> <ut.png> [js] [--init js] [--mork]'); process.exit(1); }
const DEV = 9500 + Math.floor(Math.random() * 60);
const profil = fs.mkdtempSync(path.join(os.tmpdir(), 'chrome-sk-'));
const chrome = spawn(finnChrome(), ['--headless=new', '--disable-gpu', '--disable-extensions', '--no-sandbox', `--remote-debugging-port=${DEV}`, `--user-data-dir=${profil}`, 'about:blank'], { stdio: 'ignore' });
let liste; for (let i = 0; i < 50; i++) { try { liste = await (await fetch(`http://127.0.0.1:${DEV}/json/list`)).json(); if (liste.length) break; } catch {} await new Promise((r) => setTimeout(r, 200)); }
const ws = new WebSocket(liste.find((t) => t.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
let id = 0; const v = new Map(); ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && v.has(m.id)) { v.get(m.id)(m); v.delete(m.id); } };
const kall = (me, p = {}) => new Promise((r) => { const i = ++id; v.set(i, r); ws.send(JSON.stringify({ id: i, method: me, params: p })); });
const ev = async (x) => (await kall('Runtime.evaluate', { expression: x, returnByValue: true, awaitPromise: true })).result?.result?.value;
await kall('Network.enable'); await kall('Network.setBypassServiceWorker', { bypass: true }); await kall('Page.enable');
await kall('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: true });
if (flagg.init) await kall('Page.addScriptToEvaluateOnNewDocument', { source: flagg.init });
if (flagg.mork) await kall('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: 'dark' }] });
await kall('Page.navigate', { url }); await new Promise((r) => setTimeout(r, 3500));
if (js) console.log(await ev(js));
await new Promise((r) => setTimeout(r, 1200));
const s = await kall('Page.captureScreenshot', { format: 'png' });
fs.writeFileSync(ut, Buffer.from(s.result.data, 'base64'));
if (!fs.statSync(ut).size) { console.error(`skjerm: ${ut} ble tom`); process.exitCode = 1; }
ws.close(); chrome.kill(); try { fs.rmSync(profil, { recursive: true, force: true }); } catch {}
