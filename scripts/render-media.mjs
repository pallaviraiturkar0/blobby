// Regenerates docs/media/* (state screenshots, gallery, demo video/GIF) from blobby/blob.html.
// Usage: cd scripts && npm i && node render-media.mjs   (needs ffmpeg on PATH)
import { chromium } from "playwright";
import { createServer } from "node:http";
import { readFile, mkdir, readdir, rename, rm } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const OUT = path.join(ROOT, "docs/media");
await mkdir(OUT, { recursive: true });

// Tiny static server so the demo page can drive blob.html in a same-origin iframe
let demoHtml = "";
const server = createServer(async (req, res) => {
  if (req.url === "/__demo") { res.writeHead(200, { "content-type": "text/html; charset=utf-8" }); return res.end(demoHtml); }
  try {
    const p = path.join(ROOT, decodeURIComponent(req.url.split("?")[0]));
    res.writeHead(200, { "content-type": p.endsWith(".html") ? "text/html; charset=utf-8" : "application/octet-stream" });
    res.end(await readFile(p));
  } catch { res.writeHead(404); res.end(); }
}).listen(0);
const BASE = `http://localhost:${server.address().port}`;
const STUB = "window.webkit={messageHandlers:{blob:{postMessage(){}}}};";

const STATES = [
  { name: "idle",      label: "Idle",            run: `setState('idle');say("Good morning! I'm Blobby 💚",99999)` },
  { name: "focus",     label: "Focus",           run: `setState('focus');setTimer('24:13')` },
  { name: "call",      label: "On a call",       run: `setState('call')` },
  { name: "away",      label: "Out for lunch",   run: `setSign('🍜 Out for lunch');setState('away');setTimer('back in 42:10')` },
  { name: "stretch",   label: "Stretch nudge",   run: `setState('alert');say('Stretch break! 🧘',99999)` },
  { name: "done",      label: "Focus complete",  run: `setState('happy');say('Nice!! 🍅 x3 today',99999)` },
  { name: "halloween", label: "Halloween",       run: `setFest('halloween','🎃');setState('idle')` },
  { name: "christmas", label: "Christmas",       run: `setFest('christmas','🎄');setState('idle')` },
  { name: "birthday",  label: "Your birthday",   run: `setFest('birthday','🎂');setState('happy')` },
  { name: "launch",    label: "Launch day",      run: `setFest('launch','🚀');setState('idle')` },
  { name: "diwali",    label: "Diwali",          run: `setFest('diwali','🪔');setState('idle')` },
  { name: "holi",      label: "Holi",            run: `setFest('holi','🎨');setState('idle')` },
];

const browser = await chromium.launch();

// 1) Individual state screenshots (transparent PNGs)
const shots = await browser.newPage({ viewport: { width: 240, height: 190 }, deviceScaleFactor: 2 });
await shots.addInitScript(STUB);
for (const s of STATES) {
  await shots.goto(`${BASE}/blobby/blob.html`);
  await shots.addStyleTag({ content: "*{animation-play-state:paused!important;animation-delay:-0.2s!important}" });
  await shots.evaluate(s.run);
  await shots.waitForTimeout(400);
  await shots.screenshot({ path: path.join(OUT, `state-${s.name}.png`), omitBackground: true });
}

// 2) Gallery grid
const imgs = await Promise.all(STATES.map(async s =>
  `<figure><img src="data:image/png;base64,${(await readFile(path.join(OUT, `state-${s.name}.png`))).toString("base64")}"><figcaption>${s.label}</figcaption></figure>`));
const gallery = await browser.newPage({ viewport: { width: 1200, height: 470 }, deviceScaleFactor: 2 });
await gallery.setContent(`<style>
 body{margin:0;background:radial-gradient(1200px 600px at 20% 0%,#2e1065,transparent),radial-gradient(900px 500px at 100% 100%,#0c4a6e,transparent),#0b0b14;font-family:-apple-system,system-ui,sans-serif;display:grid;grid-template-columns:repeat(6,1fr);gap:0 4px;padding:18px 20px;box-sizing:border-box;height:100vh;align-content:center}
 figure{margin:0;display:flex;flex-direction:column;align-items:center} img{width:190px} figcaption{color:#cbd5e1;font-size:14px;font-weight:600;margin-top:-4px}
</style>${imgs.join("")}`);
await gallery.screenshot({ path: path.join(OUT, "gallery.png") });

// 3) Demo video: a scripted "day in the life" on a fake desktop
const VID = path.join(ROOT, "scripts/out");
await rm(VID, { recursive: true, force: true });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 }, recordVideo: { dir: VID, size: { width: 1280, height: 720 } } });
const demo = await ctx.newPage();
demoHtml = `<style>
 html,body{margin:0;height:100%;overflow:hidden;font-family:-apple-system,system-ui,sans-serif}
 body{background:radial-gradient(900px 500px at 15% 10%,#3b0764,transparent),radial-gradient(800px 500px at 90% 90%,#0c4a6e,transparent),#0b0b14}
 .win{position:absolute;top:44px;bottom:250px;border-radius:12px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.08);backdrop-filter:blur(6px)}
 .win::before{content:"";position:absolute;top:12px;left:14px;width:52px;height:12px;background:radial-gradient(circle 6px at 6px 6px,#ff5f57 98%,transparent),radial-gradient(circle 6px at 26px 6px,#febc2e 98%,transparent),radial-gradient(circle 6px at 46px 6px,#28c840 98%,transparent)}
 .line{position:absolute;left:20px;height:8px;border-radius:4px;background:rgba(255,255,255,.08)}
 #menubar{position:absolute;top:0;left:0;right:0;height:28px;background:rgba(0,0,0,.35);color:#e2e8f0;font-size:13px;display:flex;align-items:center;padding:0 16px;gap:18px}
 #pet{position:absolute;bottom:-6px;left:520px;width:240px;height:190px;border:0;background:transparent;transition:left 2.4s ease-in-out;transform:scale(1.6);transform-origin:50% 100%}
 #cap{position:absolute;left:50%;bottom:196px;transform:translateX(-50%);display:none}
 #title{position:absolute;top:70px;left:0;right:0;text-align:center;color:#fff;font-weight:800;font-size:46px;letter-spacing:-1px;opacity:0;transform:translateY(16px) scale(.96);transition:.6s cubic-bezier(.2,.8,.2,1);text-shadow:0 6px 30px rgba(124,58,237,.6)}
 #title small{display:block;font-size:20px;font-weight:500;color:#c4b5fd;letter-spacing:0;margin-top:8px}
 #title.show{opacity:1;transform:none}
 #cursor{position:absolute;width:22px;height:22px;left:900px;top:400px;transition:left .9s ease-in-out,top .9s ease-in-out;z-index:9}
 #cursor svg{filter:drop-shadow(0 2px 3px rgba(0,0,0,.5))}
 #cursor.click svg{transform:scale(.8)}
</style>
<div id="menubar"><b></b><span>File</span><span>Edit</span><span>View</span><span style="margin-left:auto">🔨</span></div>
<div class="win" style="left:24px;width:300px"></div>
<div class="win" style="left:340px;width:600px"></div>
<div class="win" style="left:956px;width:300px"></div>
<div id="title"></div>
<iframe id="pet" src="${BASE}/blobby/blob.html"></iframe>
<div id="cursor"><svg width="22" height="22" viewBox="0 0 24 24"><path d="M3 2l7 19 2.5-7.5L20 11z" fill="#fff" stroke="#111" stroke-width="1.5"/></svg></div>`;
await demo.goto(`${BASE}/__demo`);
// fake text lines inside windows
await demo.evaluate(() => document.querySelectorAll(".win").forEach(w => { for (let i = 0; i < 9; i++) { const l = document.createElement("div"); l.className = "line"; l.style.top = 46 + i * 26 + "px"; l.style.width = 30 + Math.random() * 60 + "%"; w.appendChild(l) } }));
await demo.waitForFunction(() => document.getElementById("pet").contentWindow.setState);
await demo.evaluate(STUB.replace("window.", "document.getElementById('pet').contentWindow."));

const pet = (js) => demo.evaluate(js => document.getElementById("pet").contentWindow.eval(js), js);
const title = (t, sub = "") => demo.evaluate(([t, s]) => { const el = document.getElementById("title"); el.classList.remove("show"); setTimeout(() => { el.innerHTML = t + (s ? `<small>${s}</small>` : ""); el.classList.add("show") }, t ? 250 : 0) }, [t, sub]);
const move = (x) => demo.evaluate(x => document.getElementById("pet").style.left = x + "px", x);
const cursor = (x, y) => demo.evaluate(([x, y]) => Object.assign(document.getElementById("cursor").style, { left: x + "px", top: y + "px" }), [x, y]);
const click = () => demo.evaluate(() => { const c = document.getElementById("cursor"); c.classList.add("click"); setTimeout(() => c.classList.remove("click"), 180) });
const wait = (ms) => demo.waitForTimeout(ms);

await wait(400);
await title("Meet Blobby 💚", "a tiny productivity pet that lives on your Mac");
await pet(`setState('idle');say("Good morning! I'm Blobby 💚",3000)`);
await wait(2600);
await title("It wanders while you work");
await pet(`setState('walk','right')`); await move(820); await wait(2500);
await pet(`setState('walk','left')`); await move(470); await wait(2500);
await pet(`setState('idle')`);
await title("Click → 25-minute focus session", "headband on, countdown running");
await cursor(600, 610); await wait(1000); click();
await pet(`setState('focus');say("Let's focus! 25 min 💪",2500)`);
for (let s = 25 * 60; s > 25 * 60 - 160; s -= 40) { await pet(`setTimer('${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}')`); await wait(500); }
await pet(`setTimer('');setState('happy');say('Nice!! 🍅 x1 today. Take 5 ☕',2500)`);
await cursor(1150, 500); await wait(2600);
await title("Joins your calls 🎧", "knows when your mic is live");
await pet(`setState('call')`); await wait(3000);
await title("Out for lunch? Right-click it", "lunch · coffee · walk · BRB");
await pet(`setSign('🍜 Out for lunch');setState('away');setTimer('back in 59:58')`); await wait(3000);
await pet(`setTimer('');setState('alert');say('Stretch break! 🧘',2400)`);
await title("Gentle nudges", "stretch every hour · water every 90 min"); await wait(2800);
await pet(`setState('idle')`);
await title("Dresses up for the big days", "holidays, festivals… and your birthday");
for (const [k, p] of [["halloween", "🎃"], ["diwali", "🪔"], ["christmas", "🎄"], ["birthday", "🎂"], ["launch", "🚀"]]) { await pet(`setFest('${k}','${p}')`); await wait(1100); }
await title("Meet Blobby 💚", "github.com/pallaviraiturkar0/blobby");
await wait(2800);
await ctx.close();
await browser.close();
server.close();

const webm = path.join(VID, (await readdir(VID)).find(f => f.endsWith(".webm")));
const mp4 = path.join(OUT, "demo.mp4"), gif = path.join(OUT, "demo.gif");
execFileSync("ffmpeg", ["-y", "-loglevel", "error", "-ss", "0.6", "-i", webm, "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "22", "-movflags", "+faststart", mp4]);
execFileSync("ffmpeg", ["-y", "-loglevel", "error", "-ss", "0.6", "-i", webm, "-vf", "fps=15,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4", gif]);
await rm(VID, { recursive: true, force: true });
console.log("✓ media written to docs/media");
