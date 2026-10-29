// Single source of truth for the "Fleur-horloge" logo geometry (track A of
// docs/superpowers/specs/mockups/Main.dc.html). Used by scripts/export-brand.mjs
// to write branding/*.svg and by src/components/Logo.astro to inline the logo.
// All coordinates are in the mockup's 200x200 symbol space, dial centre (100,100).

export const PALETTE = {
  pink: '#f4b9c8',
  lavender: '#cdc4ef',
  mint: '#8fcf9f',
  ink: '#3b3350',
  cream: '#fff6e8',
  deepPink: '#e48aa3',
  ground: '#f6f1e7',
};

const SVG_NS = 'xmlns="http://www.w3.org/2000/svg"';
const ANGLES_PINK = [0, 60, 120, 180, 240, 300];
const ANGLES_LAVENDER = [30, 90, 150, 210, 270, 330];
const THIN_HAND_D = 'M100 100 L100 76';
const LEAF_HAND_D = 'M100 100 Q112 106 118 116 Q104 116 100 100 Z';

/** Visible bounds of the symbol (petal tips), used to crop lockups. */
export const SYMBOL_BOUNDS = { x: 26, y: 18, width: 148, height: 164 };

const petals = (fill, angles, cy, rx, ry, extra = '') =>
  `<g fill="${fill}"${extra}>${angles
    .map((a) => `<ellipse cx="100" cy="${cy}" rx="${rx}" ry="${ry}" transform="rotate(${a} 100 100)"/>`)
    .join('')}</g>`;

/**
 * Inner markup of the symbol (no <svg> wrapper).
 * @param {object} [opts]
 * @param {'color'|'mono'} [opts.mode] full colour, or one flat colour with a knocked-out dial
 * @param {string} [opts.mono] colour used in mono mode
 * @param {boolean} [opts.thinHand] draw the thin ink hand (dropped on the favicon)
 * @param {number} [opts.strokeScale] multiplies outline widths (favicon legibility)
 * @param {string} [opts.idPrefix] prefix for mask ids (unique per document)
 * @param {number} [opts.leafScale] enlarges the leaf-hand around the dial centre (favicon)
 * @param {string} [opts.leafAttrs] extra attributes for the leaf-hand path
 */
export function symbolMarkup({
  mode = 'color',
  mono = PALETTE.ink,
  thinHand = true,
  strokeScale = 1,
  idPrefix = 'cf',
  leafScale = 1,
  leafAttrs = '',
} = {}) {
  const sw = (w) => +(w * strokeScale).toFixed(2);
  const leafTransform =
    leafScale === 1 ? '' : ` transform="translate(100 100) scale(${leafScale}) translate(-100 -100)"`;
  const leaf = (fill, stroke) =>
    `<path data-part="leaf-hand" d="${LEAF_HAND_D}" fill="${fill}" stroke="${stroke}" stroke-width="${+(sw(3) / leafScale).toFixed(2)}" stroke-linejoin="round"${leafTransform}${leafAttrs ? ` ${leafAttrs}` : ''}/>`;
  const hand = (stroke) =>
    thinHand
      ? `<path data-part="hand" d="${THIN_HAND_D}" stroke="${stroke}" stroke-width="${sw(5)}" stroke-linecap="round"/>`
      : '';

  if (mode === 'mono') {
    // One flat colour: lavender petals become a lighter tint of it, and the
    // dial is cut out of the petals so it reads as a ring on any background.
    const maskId = `${idPrefix}-dial-cut`;
    return [
      `<defs><mask id="${maskId}"><rect width="200" height="200" fill="#ffffff"/><circle cx="100" cy="100" r="34" fill="#000000"/></mask></defs>`,
      `<g mask="url(#${maskId})">`,
      petals(mono, ANGLES_PINK, 46, 15, 28),
      petals(mono, ANGLES_LAVENDER, 50, 12, 24, ' fill-opacity="0.55"'),
      `</g>`,
      `<circle cx="100" cy="100" r="34" fill="none" stroke="${mono}" stroke-width="${sw(4)}"/>`,
      hand(mono),
      leaf(mono, mono),
      `<circle cx="100" cy="100" r="4" fill="${mono}"/>`,
    ].join('');
  }

  return [
    petals(PALETTE.pink, ANGLES_PINK, 46, 15, 28),
    petals(PALETTE.lavender, ANGLES_LAVENDER, 50, 12, 24),
    `<circle cx="100" cy="100" r="34" fill="${PALETTE.cream}" stroke="${PALETTE.ink}" stroke-width="${sw(4)}"/>`,
    hand(PALETTE.ink),
    leaf(PALETTE.mint, PALETTE.ink),
    `<circle cx="100" cy="100" r="4" fill="${PALETTE.ink}"/>`,
  ].join('');
}

const fmt = (n) => +n.toFixed(2);

function svgDoc({ viewBox, width, height, label, body }) {
  const size = width && height ? ` width="${fmt(width)}" height="${fmt(height)}"` : '';
  return `<svg ${SVG_NS} viewBox="${viewBox.map(fmt).join(' ')}"${size} role="img" aria-label="${label}"><title>${label}</title>${body}</svg>`;
}

/** Standalone symbol, square 200x200 (mockup framing). */
export function symbolSvg(opts = {}) {
  const { viewBox = [0, 0, 200, 200], label = 'ChronoFlore', ...rest } = opts;
  return svgDoc({ viewBox, label, body: symbolMarkup(rest) });
}

/** Favicon: petals + dial + leaf-hand only, tight crop, bolder outlines. */
export function faviconSvg() {
  return svgDoc({
    viewBox: [14, 14, 172, 172],
    label: 'ChronoFlore',
    body: symbolMarkup({ thinHand: false, strokeScale: 2, leafScale: 1.5 }),
  });
}

function wordmarkMarkup(wordmark, x, y, scale) {
  const t = `translate(${fmt(x)} ${fmt(y)}) scale(${fmt(scale * 1000) / 1000})`;
  return (
    `<g transform="${t}">` +
    `<path data-wordmark="chrono" fill="${PALETTE.ink}" d="${wordmark.chrono}"/>` +
    `<path data-wordmark="flore" fill="${PALETTE.deepPink}" d="${wordmark.flore}"/>` +
    `</g>`
  );
}

/** Nested 200x200 viewport so CSS transform-box: view-box pivots on the dial centre. */
function nestedSymbol(x, y, size, opts) {
  return `<svg x="${fmt(x)}" y="${fmt(y)}" width="${fmt(size)}" height="${fmt(size)}" viewBox="0 0 200 200" overflow="visible">${symbolMarkup(opts)}</svg>`;
}

/**
 * Full lockup (symbol + vectorised wordmark).
 * @param {'horizontal'|'stacked'} variant
 * @param {{chrono: string, flore: string, xMin: number, xMax: number, yMin: number, yMax: number, fontSize: number}} wordmark
 *   paths laid out at `fontSize`, baseline at y=0, from scripts/export-brand.mjs
 * @param {object} [symbolOpts] forwarded to symbolMarkup
 */
export function logoLayout(variant, wordmark, symbolOpts = {}) {
  const pad = 8;
  const b = SYMBOL_BOUNDS;
  const textW = wordmark.xMax - wordmark.xMin;
  const textH = wordmark.yMax - wordmark.yMin; // yMin is negative (above baseline)

  if (variant === 'stacked') {
    // Mockup ratio: 46px wordmark under a 220px (200-unit) symbol box.
    const scale = 42 / wordmark.fontSize;
    const w = textW * scale;
    const width = Math.max(b.width, w) + pad * 2;
    const symX = (width - 200) / 2;
    const symY = pad - b.y;
    const textTop = pad + b.height + 22;
    const tx = (width - w) / 2 - wordmark.xMin * scale;
    const ty = textTop - wordmark.yMin * scale;
    const height = textTop + textH * scale + pad;
    return {
      width,
      height,
      body: nestedSymbol(symX, symY, 200, symbolOpts) + wordmarkMarkup(wordmark, tx, ty, scale),
    };
  }

  // Horizontal: wordmark x-height block centred on the dial.
  const scale = 92 / wordmark.fontSize;
  const symX = pad - b.x;
  const symY = pad - b.y;
  const textLeft = pad + b.width + 26;
  const tx = textLeft - wordmark.xMin * scale;
  const ty = symY + 100 - (wordmark.yMin + textH / 2) * scale;
  const width = textLeft + textW * scale + pad;
  const height = b.height + pad * 2;
  return {
    width,
    height,
    body: nestedSymbol(symX, symY, 200, symbolOpts) + wordmarkMarkup(wordmark, tx, ty, scale),
  };
}

export function logoSvg(variant, wordmark, opts = {}) {
  const { width, height, body } = logoLayout(variant, wordmark, opts);
  return svgDoc({ viewBox: [0, 0, width, height], label: 'ChronoFlore', body });
}
