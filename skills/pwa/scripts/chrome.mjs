// Finner Chrome for skriptene her. CHROME overstyrer. Ellers vanlige steder på Linux og
// macOS, og til slutt Chrome for Testing fra puppeteer- eller Playwright-cachen (nyeste
// først): på en Mac uten Chrome installert er det ofte den eneste som finnes.
import fs from 'node:fs'; import os from 'node:os'; import path from 'node:path';

const FASTE = [
  '/usr/bin/google-chrome', '/usr/bin/google-chrome-stable', '/usr/bin/chromium', '/usr/bin/chromium-browser',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
];
const CACHER = ['.cache/puppeteer/chrome', 'Library/Caches/ms-playwright', '.cache/ms-playwright'];
const INNI = ['Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing', 'Chromium.app/Contents/MacOS/Chromium', 'chrome'];

const mapper = (m) => { try { return fs.readdirSync(m).map((n) => path.join(m, n)); } catch { return []; } };

export function finnChrome() {
  if (process.env.CHROME) {
    if (!fs.existsSync(process.env.CHROME)) throw new Error(`CHROME=${process.env.CHROME} finnes ikke`);
    return process.env.CHROME;
  }
  const fast = FASTE.find((f) => fs.existsSync(f));
  if (fast) return fast;
  // <cache>/<versjon>/<plattform>/<program>, f.eks. chromium-1234/chrome-mac-arm64/Google Chrome for Testing.app/…
  const funnet = CACHER.flatMap((c) => mapper(path.join(os.homedir(), c)))
    .sort((a, b) => b.localeCompare(a, 'en', { numeric: true }))
    .flatMap((v) => mapper(v).flatMap((p) => INNI.map((i) => path.join(p, i))))
    .find((f) => fs.existsSync(f) && fs.statSync(f).isFile());
  if (funnet) return funnet;
  throw new Error('Fant ikke Chrome. Sett CHROME=<sti>, eller: npx @puppeteer/browsers install chrome@stable');
}
