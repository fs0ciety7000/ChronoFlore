// Renders the two raster assets from the live 3D diorama:
//   public/poster.webp  the island at progress 0 (the poster shown before the 3D loads)
//   public/og.png       1200x630 share card: the island at dusk + logo + title
// Builds the site, serves it with `astro preview`, drives headless Chromium
// with software WebGL (swiftshader) and waits for data-state="live".
// Run: npm run poster
import { execFileSync, spawn } from 'node:child_process';
import { existsSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import sharp from 'sharp';

const siteDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const publicDir = join(siteDir, 'public');
const require = createRequire(import.meta.url);
const PORT = 4339;
const ORIGIN = `http://localhost:${PORT}`;
const POSTER_PX = 1000; // square; Hero.astro lays it out in a --focus-size square
const POSTER_BYTES = 200 * 1024;
const DUSK_PROGRESS = 0.5; // rose twilight (src/scripts/timeline.ts, DUSK keyframes)
const VIEWPORT = { width: 1440, height: 900 };
const WEBGL_ARGS = ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'];

const fallback = process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium';
const executablePath = existsSync(chromium.executablePath()) ? undefined : existsSync(fallback) ? fallback : undefined;

async function waitForServer() {
  for (let i = 0; i < 100; i++) {
    try {
      if ((await fetch(ORIGIN)).ok) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 300));
  }
  throw new Error('preview server did not start');
}

/**
 * Captures the island square (as laid out by the hero: --focus-*) of the live
 * canvas at the given scroll progress, with the glide pinned to the hero
 * composition so the island keeps its hero size and place.
 */
async function captureIsland(browser, progress) {
  const page = await browser.newPage({ viewport: VIEWPORT, deviceScaleFactor: 2 });
  try {
    // The glide (island moving into the right-hand lane) is derived from
    // window.scrollY by src/scripts/diorama/loader.ts; ScrollTrigger reads
    // pageYOffset, so pinning scrollY keeps the hero framing at any progress.
    await page.addInitScript(() => Object.defineProperty(window, 'scrollY', { get: () => 0, configurable: true }));
    await page.goto(ORIGIN, { waitUntil: 'load' });
    await page.waitForSelector('#diorama[data-state="live"]', { timeout: 60_000 });
    await page.evaluate((f) => {
      const max = document.documentElement.scrollHeight - innerHeight;
      scrollTo({ top: max * f, behavior: 'instant' });
    }, progress);
    // Show only the canvas: no header, copy or poster above it.
    await page.addStyleTag({
      content: '* { visibility: hidden !important } #diorama, #diorama canvas { visibility: visible !important } #diorama img { display: none }',
    });
    // The scene eases toward the target progress; let it settle.
    await page.waitForTimeout(4000);
    const island = await page.evaluate(() => document.getElementById('diorama').dataset.island);
    const [x, y, r] = island.split(',').map(Number);
    // dataset.island is the island radius on screen; the poster square is the
    // hero's --focus-size (the camera is framed on it, 31 m across).
    const size = await page.evaluate(() => parseFloat(getComputedStyle(document.querySelector('#diorama img')).width));
    const clip = { x: x - size / 2, y: y - size / 2, width: size, height: size };
    console.log(`progress ${progress}: island ${x},${y} r=${r}, square ${size}px`);
    return await page.screenshot({ clip, type: 'png' });
  } finally {
    await page.close();
  }
}

async function writePoster(png) {
  let quality = 80;
  let buf;
  do {
    buf = await sharp(png).resize(POSTER_PX, POSTER_PX).webp({ quality, effort: 6 }).toBuffer();
    quality -= 5;
  } while (buf.length > POSTER_BYTES && quality > 30);
  writeFileSync(join(publicDir, 'poster.webp'), buf);
  console.log(`poster.webp ${buf.length} bytes (quality ${quality + 5})`);
}

const font = (pkg, file, weight, style) => {
  const data = readFileSync(require.resolve(`${pkg}/files/${file}`)).toString('base64');
  return `@font-face{font-family:'${pkg.split('/')[1] === 'fredoka' ? 'Fredoka' : 'Nunito'}';font-weight:${weight};font-style:${style};src:url(data:font/woff2;base64,${data}) format('woff2')}`;
};

async function writeOg(browser, islandPng) {
  // Sky of the dusk scene, sampled from the capture so the card is seamless.
  const { data } = await sharp(islandPng).extract({ left: 4, top: 4, width: 1, height: 1 }).raw().toBuffer({ resolveWithObject: true });
  const sky = `rgb(${data[0]},${data[1]},${data[2]})`;
  const logo = readFileSync(join(siteDir, '..', 'branding', 'chronoflore-logo-horizontal.svg'), 'utf8');
  const logoUrl = `data:image/svg+xml;base64,${Buffer.from(logo).toString('base64')}`;
  const island = `data:image/png;base64,${islandPng.toString('base64')}`;
  const html = `<!doctype html><meta charset="utf-8"><style>
${font('@fontsource/fredoka', 'fredoka-latin-600-normal.woff2', 600, 'normal')}
${font('@fontsource/nunito', 'nunito-latin-700-normal.woff2', 700, 'normal')}
*{box-sizing:border-box;margin:0}
html,body{width:1200px;height:630px;overflow:hidden}
body{position:relative;background:${sky};font-family:'Fredoka',sans-serif;color:#2a2340}
/* A gentle darkening toward the corners. */
body::before{content:'';position:absolute;inset:0;background:
  radial-gradient(120% 120% at 50% 50%, transparent 55%, rgba(60,30,60,.22))}
.island{position:absolute;right:30px;top:-20px;width:660px;height:660px;
  -webkit-mask-image:radial-gradient(closest-side, #000 72%, transparent);mask-image:radial-gradient(closest-side, #000 72%, transparent)}
.copy{position:absolute;left:72px;top:0;bottom:0;width:560px;display:flex;flex-direction:column;justify-content:center;gap:34px}
.plate{align-self:flex-start;background:#fff6e8;border-radius:22px;padding:16px 26px 16px 18px;box-shadow:0 10px 30px rgba(60,30,60,.22)}
.plate img{display:block;height:64px}
h1{font-weight:600;font-size:60px;line-height:1.06;letter-spacing:-.02em;text-wrap:balance}
p{font-family:'Nunito',sans-serif;font-weight:700;font-size:25px;color:#3b2f4e}
</style>
<img class="island" src="${island}" alt="">
<div class="copy">
  <div class="plate"><img src="${logoUrl}" alt="ChronoFlore"></div>
  <h1>Huit heures de sommeil. Toute une flore à capturer.</h1>
  <p>Jeu d'action-arcade · en développement</p>
</div>`;
  const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
  try {
    await page.setContent(html, { waitUntil: 'load' });
    await page.evaluate(() => document.fonts.ready);
    const png = await page.screenshot({ type: 'png' });
    const out = await sharp(png).png({ compressionLevel: 9, palette: false }).toBuffer();
    writeFileSync(join(publicDir, 'og.png'), out);
    console.log(`og.png ${out.length} bytes`);
  } finally {
    await page.close();
  }
}

execFileSync('npm', ['run', 'build'], { cwd: siteDir, stdio: 'inherit' });
const server = spawn('npx', ['astro', 'preview', '--port', String(PORT)], { cwd: siteDir, stdio: 'ignore' });
let browser;
try {
  await waitForServer();
  browser = await chromium.launch({ executablePath, args: WEBGL_ARGS });
  await writePoster(await captureIsland(browser, 0));
  await writeOg(browser, await captureIsland(browser, DUSK_PROGRESS));
  console.log(`done: ${statSync(join(publicDir, 'poster.webp')).size} / ${statSync(join(publicDir, 'og.png')).size} bytes`);
} finally {
  await browser?.close();
  server.kill();
}
