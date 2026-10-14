// Etter bygget: skallet byttes som ett stykke (pwa-skillen, regel 2). Hasher alle filene
// i <dist> (navn og innhold) til et cachenavn, og skriver det og lista over filene inn i
// <sw.js> over plassholderne
//   const CACHE = '<prefiks>-dev';    og    const SKALL = [/* SKALL */];
// Endres én fil, får service workeren nytt navn og henter hele skallet på nytt. Mangler
// plassholderne, feiler skriptet, i stedet for å levere en service worker som aldri bytter.
// Bruk: node skall-til-sw.mjs <dist> <sw.js> [--utenfor <regex>]
// --utenfor: filer (sti relativt til <dist>) som holdes utenfor skallet, f.eks. en tung,
// sjelden lat modul som service workeren cacher for seg: --utenfor '^assets/scene3d-[\w-]+\.js$'
import crypto from 'node:crypto'; import fs from 'node:fs'; import path from 'node:path';

const pos = []; let utenfor = null; const arg = process.argv.slice(2);
for (let i = 0; i < arg.length; i++) {
  if (arg[i] === '--utenfor') utenfor = new RegExp(arg[++i]);
  else pos.push(arg[i]);
}
const [dist, swSti] = pos;
if (!dist || !swSti) { console.error('bruk: node skall-til-sw.mjs <dist> <sw.js> [--utenfor <regex>]'); process.exit(1); }

const rel = (f) => path.relative(dist, f).split(path.sep).join('/');
const filerUnder = (mappe) => fs.readdirSync(mappe, { withFileTypes: true }).flatMap((f) => {
  const full = path.join(mappe, f.name);
  return f.isDirectory() ? filerUnder(full) : [rel(full)];
});
const sw = rel(path.resolve(swSti));
const filer = filerUnder(dist).filter((f) => f !== sw && !utenfor?.test(f)).sort();

const hash = crypto.createHash('sha256');
for (const f of filer) hash.update(f).update('\0').update(fs.readFileSync(path.join(dist, f)));

const fra = fs.readFileSync(swSti, 'utf8');
const plass = /const CACHE = '([\w.-]+)-dev'/.exec(fra);
if (!plass || !fra.includes('[/* SKALL */]')) {
  console.error(`${swSti} mangler plassholderne: const CACHE = '<prefiks>-dev' og const SKALL = [/* SKALL */]`);
  process.exit(1);
}
const cache = `${plass[1]}-${hash.digest('hex').slice(0, 12)}`;
const skall = filer.map((f) => (f === 'index.html' ? '/' : `/${f}`));
fs.writeFileSync(swSti, fra.replace(plass[0], `const CACHE = '${cache}'`).replace('[/* SKALL */]', JSON.stringify(skall)));
console.log(`${cache}: ${skall.length} filer i skallet`);
