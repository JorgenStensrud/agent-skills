// Sjekker iOS-runden mot en kjørende server: faner, rulleminne, aktiv fane, sticky
// dagoverskrift, bunnark, sveip med ekte berøring, Dynamic Type, ikonmerke, kalender.
import { spawn } from 'node:child_process'; import fs from 'node:fs'; import os from 'node:os'; import path from 'node:path';
const BASIS = process.env.UX_BASIS || 'http://127.0.0.1:3403';
const UT = process.env.UX_UT || '/tmp/ios'; fs.mkdirSync(UT, { recursive: true });
const DEV = 9600 + Math.floor(Math.random()*60);
const profil = fs.mkdtempSync(path.join(os.tmpdir(),'chrome-ios-'));
const chrome = spawn('/usr/bin/google-chrome',['--headless=new','--disable-gpu','--disable-extensions','--no-sandbox',`--remote-debugging-port=${DEV}`,`--user-data-dir=${profil}`,'about:blank'],{stdio:'ignore'});
let liste; for(let i=0;i<50;i++){try{liste=await (await fetch(`http://127.0.0.1:${DEV}/json/list`)).json();if(liste.length)break;}catch{}await new Promise(r=>setTimeout(r,200));}
const ws=new WebSocket(liste.find(t=>t.type==='page').webSocketDebuggerUrl); await new Promise(r=>(ws.onopen=r));
let id=0; const v=new Map(); const feil=[]; ws.onmessage=(e)=>{const m=JSON.parse(e.data); if(m.method==='Runtime.exceptionThrown') feil.push((m.params.exceptionDetails.exception?.description||m.params.exceptionDetails.text).slice(0,160)); if(m.id&&v.has(m.id)){v.get(m.id)(m);v.delete(m.id);}};
const kall=(me,p={})=>new Promise(r=>{const i=++id;v.set(i,r);ws.send(JSON.stringify({id:i,method:me,params:p}));});
const ev=async(x)=>{const r=await kall('Runtime.evaluate',{expression:x,returnByValue:true,awaitPromise:true}); if(r.result?.exceptionDetails) return 'UNNTAK: '+(r.result.exceptionDetails.exception?.description||'').slice(0,200); return r.result?.result?.value;};
const vent=(ms)=>new Promise(r=>setTimeout(r,ms));
const gaa=async(h,ms=2500)=>{await kall('Page.navigate',{url:'about:blank'});await vent(150);await kall('Page.navigate',{url:BASIS+'/'+h});await vent(ms);};
const bilde=async(navn)=>{const r=await kall('Page.captureScreenshot',{format:'png'});fs.writeFileSync(path.join(UT,navn+'.png'),Buffer.from(r.result.data,'base64'));};
async function sveip(x0,x1,y,trinn=10){await kall('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:x0,y}]});for(let i=1;i<=trinn;i++){await kall('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:x0+(x1-x0)*i/trinn,y}]});await vent(16);}await kall('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});}
async function trykk(x,y){await kall('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x,y}]});await vent(30);await kall('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});}
await kall('Network.enable'); await kall('Network.setBypassServiceWorker',{bypass:true}); await kall('Page.enable'); await kall('Runtime.enable');
await kall('Page.addScriptToEvaluateOnNewDocument',{source:(process.env.MORK?"localStorage.setItem('tema','mork');":"")+"window.__merke=[]; navigator.share=(d)=>{window.__delt={title:d.title,text:d.text,filer:(d.files||[]).length};return Promise.resolve();}; navigator.canShare=()=>true; navigator.setAppBadge=(n)=>{window.__merke.push(n);return Promise.resolve();};"});
await kall('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
await kall('Emulation.setTouchEmulationEnabled',{enabled:true});
const ut = {};

// 1 Faner og ingresser
await gaa('#/praktisk');
ut.faner = await ev("[...document.querySelectorAll('.faner a')].map(a=>a.textContent.trim())");
ut.italienskRad = await ev("Boolean(document.querySelector('a.rad[href=\"#/italiensk\"]'))");
ut.ingressPraktisk = await ev("document.querySelectorAll('.ingress').length");
ut.fontHtml = await ev("getComputedStyle(document.documentElement).fontSize");
ut.fontRadSpan = await ev("getComputedStyle(document.querySelector('.rad-tekst span')).fontSize");
ut.merke = await ev("window.__merke");
await bilde('praktisk');

// 2 Rulleminne: Utforsk → sted → tilbake
await gaa('#/utforsk', 3000);
await ev("window.scrollTo(0, 900)"); await vent(200);
const y0 = await ev("window.scrollY");
const stedHref = await ev("(document.querySelector('a[href^=\"#/sted/\"]')||{}).getAttribute?.('href')");
await ev(`location.hash='${stedHref}'`); await vent(1500);
const ySted = await ev("window.scrollY");
await ev("history.back()"); await vent(1500);
ut.rulleminne = { foer: y0, paaSted: ySted, tilbake: await ev("window.scrollY"), rute: await ev("location.hash") };
// 3 Aktiv fane → toppen
const fane = await ev("(()=>{const a=document.querySelector('.faner a.aktiv');const r=a.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2,t:a.textContent.trim()};})()");
await kall('Input.dispatchMouseEvent',{type:'mousePressed',x:fane.x,y:fane.y,button:'left',clickCount:1});
await kall('Input.dispatchMouseEvent',{type:'mouseReleased',x:fane.x,y:fane.y,button:'left',clickCount:1});
await vent(1200);
ut.aktivFane = { fane: fane.t, scrollY: await ev("window.scrollY"), hash: await ev("location.hash") };

// 4 Sticky dagoverskrift
await gaa('#/program', 3000);
await ev("window.scrollTo(0, 1400)"); await vent(300);
ut.sticky = await ev("(()=>{const hs=[...document.querySelectorAll('.dag header')].map(h=>({top:Math.round(h.getBoundingClientRect().top),pos:getComputedStyle(h).position,bg:getComputedStyle(h).backgroundColor}));return {pos:hs[0].pos, festet:hs.filter(h=>h.top===0).length, bg:hs[0].bg};})()");
ut.kalenderLenke = await ev("(document.querySelector('.kalender-lenke a')||{}).href");
await bilde('program-sticky');

// 5 Bunnark
await ev("window.scrollTo(0, 0)"); await vent(200);
const meny = await ev("(()=>{const b=document.querySelector('.rad-meny');b.scrollIntoView({block:'center'});const r=b.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()");
await vent(200);
await kall('Input.dispatchMouseEvent',{type:'mousePressed',x:meny.x,y:meny.y,button:'left',clickCount:1});
await kall('Input.dispatchMouseEvent',{type:'mouseReleased',x:meny.x,y:meny.y,button:'left',clickCount:1});
await vent(500);
ut.ark = await ev("(()=>{const a=document.querySelector('.ark');return a&&{vist:a.classList.contains('vist'),valg:[...a.querySelectorAll('.ark-valg button')].map(b=>b.textContent),tittel:a.querySelector('.ark-tittel')?.textContent.slice(0,40),transform:getComputedStyle(a).transform};})()");
await bilde('ark');
await kall('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape'}); await vent(400);
ut.arkLukket = await ev("!document.querySelector('.ark-bak')");
// Bjella i ark
const varselKnapp = await ev("(()=>{const b=document.querySelector('.rad-meny');const r=b.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()");
await kall('Input.dispatchMouseEvent',{type:'mousePressed',x:varselKnapp.x,y:varselKnapp.y,button:'left',clickCount:1});
await kall('Input.dispatchMouseEvent',{type:'mouseReleased',x:varselKnapp.x,y:varselKnapp.y,button:'left',clickCount:1});
await vent(400);
await ev("[...document.querySelectorAll('.ark-valg button')].find(b=>/Varsel|Varsle/.test(b.textContent))?.click()"); await vent(500);
ut.bjelleArk = await ev("(()=>{const a=document.querySelector('.ark');return a&&{tid:Boolean(a.querySelector('input[type=time]')),valg:[...a.querySelectorAll('.varsel-valg button')].map(b=>b.textContent)};})()");
await bilde('ark-bjelle');
await kall('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape'}); await vent(300);

// 6 Sveip med ekte berøring på pakkelista
await gaa('#/pakke', 3000);
const rad = await ev("(()=>{const r=document.querySelector('.rad-boks > .rad');r.scrollIntoView({block:'center'});const b=r.getBoundingClientRect();return {y:b.y+b.height/2,pakket:r.classList.contains('pakket'),tekst:r.textContent.trim().slice(0,30)};})()");
await vent(200);
await ev("window.__scrollFoer=window.scrollY");
await sveip(330, 150, rad.y); await vent(400);
ut.sveipVenstre = await ev("(()=>{const r=document.querySelector('.rad-boks > .rad');return {transform:r.style.transform,klasse:r.parentElement.className,scrollDiff:window.scrollY-window.__scrollFoer};})()");
await bilde('sveip-venstre');
await trykk(120, rad.y); await vent(400);
ut.sveipLukket = await ev("document.querySelector('.rad-boks > .rad').style.transform");
// Kanten: start innenfor 24 px skal ikke sveipe
await sveip(10, 200, rad.y); await vent(300);
ut.kantSveip = await ev("document.querySelector('.rad-boks > .rad').style.transform");
// Kort sveip høyre → kryss av
await sveip(120, 200, rad.y); await vent(1500);
ut.sveipHoyre = { foer: rad.pakket, etter: await ev("(()=>{const r=document.querySelector('.rad-boks > .rad');return r.classList.contains('pakket');})()") };
// Sett tilbake
await sveip(120, 200, rad.y); await vent(1200);
ut.sveipTilbake = await ev("document.querySelector('.rad-boks > .rad').classList.contains('pakket')");
// Loddrett drag på raden skal rulle, ikke sveipe
await ev("window.scrollTo(0,0)"); await vent(200);
const rad2 = await ev("(()=>{const r=document.querySelector('.rad-boks > .rad');const b=r.getBoundingClientRect();return b.y+b.height/2;})()");
await kall('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:200,y:rad2}]});
for(let i=1;i<=10;i++){await kall('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:200+i,y:rad2-i*20}]});await vent(16);}
await kall('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]}); await vent(400);
ut.loddrett = { scrollY: await ev("window.scrollY"), transform: await ev("document.querySelector('.rad-boks > .rad').style.transform") };

// 7 Kalender-endepunkt og dagbok-del-knapp
ut.ics = await ev(`fetch('/api/turer/gardasjoen-2026/kalender.ics').then(r=>r.headers.get('content-type'))`);
await gaa('#/dagbok', 2500);
ut.delKnapp = await ev("[...document.querySelectorAll('.dagbok-knapper button')].map(b=>b.textContent).slice(0,4)");
await ev("[...document.querySelectorAll('.dagbok-knapper button')].find(b=>b.textContent==='Del')?.click()"); await vent(1500);
ut.delt = await ev("window.__delt");
await gaa('#/sider', 2000);
const sideHref = await ev("(document.querySelector('a[href^=\"#/sider/\"]')||{}).getAttribute?.('href')");
if (sideHref) { await ev(`location.hash='${sideHref}'`); await vent(1200); await ev("[...document.querySelectorAll('button')].find(b=>b.textContent==='Del')?.click()"); await vent(500); ut.deltSide = await ev("window.__delt"); }
// Hjem: høyden på hver del
await gaa('#/', 3000);
ut.hjemDeler = await ev("[...document.querySelector('main').firstElementChild.children].flatMap(e=>e.classList.contains('side')?[...e.children]:[e]).map(e=>(e.className||e.tagName).toString().slice(0,20)+':'+Math.round(e.getBoundingClientRect().height))");
// Program: små mål
await gaa('#/program', 3000);
ut.smaa = await ev("[...document.querySelectorAll('a,button,input,select,textarea,[role=button]')].filter(e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0&&(r.height<44||r.width<32)&&getComputedStyle(e).visibility!=='hidden';}).map(e=>e.tagName+'.'+e.className+':'+e.textContent.trim().slice(0,30)+':'+Math.round(e.getBoundingClientRect().height))");
ut.unntak = feil;
console.log(JSON.stringify(ut, null, 1));
ws.close(); chrome.kill(); try{fs.rmSync(profil,{recursive:true,force:true});}catch{}
