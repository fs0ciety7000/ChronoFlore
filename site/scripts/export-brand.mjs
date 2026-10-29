// Generates every brand asset from src/brand/geometry.mjs:
//   branding/*.svg, branding/png/*.png, site/public/favicon.{svg,ico},
//   site/public/apple-touch-icon.png, game/icon.svg and src/brand/wordmark.json.
// The wordmark is Fredoka 600 (from @fontsource) converted to paths with opentype.js.
// Run: npm run brand
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import opentype from 'opentype.js';
import pngToIco from 'png-to-ico';
import { chromium } from 'playwright';
import { PALETTE, faviconSvg, logoSvg, symbolSvg } from '../src/brand/geometry.mjs';

const siteDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = resolve(siteDir, '..');
const brandingDir = join(repoRoot, 'branding');
const pngDir = join(brandingDir, 'png');
const publicDir = join(siteDir, 'public');
const require = createRequire(import.meta.url);

const FONT_SIZE = 100;
const LETTER_SPACING = -0.01; // em, as in the mockup

function write(path, content) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content);
  console.log(`wrote ${path.slice(repoRoot.length + 1)}`);
}

/** Lay out "Chrono" + "Flore" as two path strings, baseline at y=0. */
function buildWordmark() {
  const fontFile = require.resolve('@fontsource/fredoka/files/fredoka-latin-600-normal.woff');
  const buf = readFileSync(fontFile);
  const font = opentype.parse(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength));
  const scale = FONT_SIZE / font.unitsPerEm;
  const words = { chrono: 'Chrono', flore: 'Flore' };
  const out = {};
  const box = { xMin: Infinity, yMin: Infinity, xMax: -Infinity, yMax: -Infinity };
  let x = 0;
  let prev = null;
  for (const [key, text] of Object.entries(words)) {
    const path = new opentype.Path();
    for (const glyph of font.stringToGlyphs(text)) {
      if (prev) x += font.getKerningValue(prev, glyph) * scale;
      path.extend(glyph.getPath(x, 0, FONT_SIZE));
      x += glyph.advanceWidth * scale + LETTER_SPACING * FONT_SIZE;
      prev = glyph;
    }
    const bb = path.getBoundingBox();
    box.xMin = Math.min(box.xMin, bb.x1);
    box.yMin = Math.min(box.yMin, bb.y1);
    box.xMax = Math.max(box.xMax, bb.x2);
    box.yMax = Math.max(box.yMax, bb.y2);
    out[key] = path.toPathData(2);
  }
  const r = (n) => +n.toFixed(2);
  return {
    fontSize: FONT_SIZE,
    xMin: r(box.xMin),
    yMin: r(box.yMin),
    xMax: r(box.xMax),
    yMax: r(box.yMax),
    ...out,
  };
}

// Prefer Playwright's own browser; fall back to a preinstalled Chromium when
// the bundled revision is missing (override with CHROMIUM_PATH).
async function launchBrowser() {
  const fallback = process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium';
  try {
    return await chromium.launch();
  } catch (error) {
    if (!existsSync(fallback)) throw error;
    return chromium.launch({ executablePath: fallback });
  }
}

async function rasterise(browser, svg, size, background = 'transparent', inset = 0) {
  const page = await browser.newPage({ viewport: { width: size, height: size } });
  const inner = size - inset * 2;
  const src = `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`;
  await page.setContent(
    `<html><body style="margin:0;background:${background}">` +
      `<img src="${src}" width="${inner}" height="${inner}" style="display:block;margin:${inset}px"></body></html>`,
  );
  await page.waitForFunction(() => document.images[0]?.complete);
  const png = await page.screenshot({ omitBackground: background === 'transparent' });
  await page.close();
  return png;
}

async function main() {
  const wordmark = buildWordmark();
  write(join(siteDir, 'src/brand/wordmark.json'), `${JSON.stringify(wordmark, null, 2)}\n`);

  const symbol = `${symbolSvg()}\n`;
  write(join(brandingDir, 'chronoflore-symbol.svg'), symbol);
  write(join(brandingDir, 'chronoflore-logo-horizontal.svg'), `${logoSvg('horizontal', wordmark)}\n`);
  write(join(brandingDir, 'chronoflore-logo-stacked.svg'), `${logoSvg('stacked', wordmark)}\n`);
  write(
    join(brandingDir, 'chronoflore-symbol-mono-ink.svg'),
    `${symbolSvg({ mode: 'mono', mono: PALETTE.ink, idPrefix: 'cf-ink' })}\n`,
  );
  write(
    join(brandingDir, 'chronoflore-symbol-mono-cream.svg'),
    `${symbolSvg({ mode: 'mono', mono: PALETTE.cream, idPrefix: 'cf-cream' })}\n`,
  );
  const favicon = `${faviconSvg()}\n`;
  write(join(brandingDir, 'chronoflore-favicon.svg'), favicon);
  write(join(publicDir, 'favicon.svg'), favicon);
  write(join(repoRoot, 'game/icon.svg'), symbol);

  const browser = await launchBrowser();
  try {
    for (const size of [512, 1024]) {
      write(join(pngDir, `chronoflore-symbol-${size}.png`), await rasterise(browser, symbol, size));
    }
    // iOS fills transparency with black: use the day ground and a safe inset.
    write(join(publicDir, 'apple-touch-icon.png'), await rasterise(browser, symbol, 180, PALETTE.ground, 6));
    const icoPngs = [];
    for (const size of [16, 32, 48]) icoPngs.push(await rasterise(browser, favicon, size));
    write(join(pngDir, 'chronoflore-favicon-16.png'), icoPngs[0]);
    write(join(publicDir, 'favicon.ico'), await pngToIco(icoPngs));
  } finally {
    await browser.close();
  }
}

await main();
