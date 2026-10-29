import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '../../..');
const brandingDir = join(repoRoot, 'branding');

const EXPECTED_SVGS = [
  'chronoflore-symbol.svg',
  'chronoflore-logo-horizontal.svg',
  'chronoflore-logo-stacked.svg',
  'chronoflore-symbol-mono-ink.svg',
  'chronoflore-symbol-mono-cream.svg',
];

/**
 * Minimal XML well-formedness check: balanced tags, quoted attributes,
 * single root element, no stray text outside the root.
 * Returns an error message, or null when the document is well-formed.
 */
function xmlError(source: string): string | null {
  const body = source
    .replace(/^﻿/, '')
    .replace(/<\?xml[\s\S]*?\?>/, '')
    .replace(/<!--[\s\S]*?-->/g, '');
  const tagRe = /<(\/?)([A-Za-z_][\w:.-]*)((?:\s+[\w:.-]+\s*=\s*(?:"[^"<]*"|'[^'<]*'))*)\s*(\/?)>/g;
  const stack: string[] = [];
  let roots = 0;
  let last = 0;
  for (let m = tagRe.exec(body); m; m = tagRe.exec(body)) {
    const between = body.slice(last, m.index);
    if (between.includes('<') || between.includes('>')) return `malformed markup near offset ${last}`;
    if (stack.length === 0 && between.trim() !== '') return 'text outside root element';
    last = tagRe.lastIndex;
    const [, closing, name, , selfClosing] = m;
    if (closing) {
      if (stack.pop() !== name) return `unexpected </${name}>`;
      continue;
    }
    if (stack.length === 0) roots += 1;
    if (!selfClosing) stack.push(name);
  }
  const tail = body.slice(last);
  if (tail.includes('<') || tail.includes('>') || tail.trim() !== '') return 'trailing content';
  if (stack.length) return `unclosed <${stack.at(-1)}>`;
  if (roots !== 1) return `expected 1 root element, got ${roots}`;
  return null;
}

const read = (path: string) => readFileSync(path, 'utf8');

describe('xmlError helper', () => {
  it('accepts well-formed and rejects malformed markup', () => {
    expect(xmlError('<svg viewBox="0 0 1 1"><g><path d="M0 0"/></g></svg>')).toBeNull();
    expect(xmlError('<svg><g></svg>')).not.toBeNull();
    expect(xmlError('<svg a=1></svg>')).not.toBeNull();
  });
});

describe('branding SVGs', () => {
  it('ships every expected file', () => {
    const present = readdirSync(brandingDir);
    for (const name of EXPECTED_SVGS) expect(present).toContain(name);
  });

  const svgFiles = [
    ...readdirSync(brandingDir)
      .filter((f) => f.endsWith('.svg'))
      .map((f) => join(brandingDir, f)),
    join(repoRoot, 'site/public/favicon.svg'),
    join(repoRoot, 'game/icon.svg'),
  ];

  it.each(svgFiles)('%s is valid, vectorised SVG', (file) => {
    expect(existsSync(file)).toBe(true);
    const svg = read(file);
    expect(xmlError(svg)).toBeNull();
    expect(svg).toMatch(/<svg\b[^>]*\sviewBox="[\d.\s-]+"/);
    expect(svg).toMatch(/xmlns="http:\/\/www\.w3\.org\/2000\/svg"/);
    expect(svg).not.toMatch(/<text\b/);
    expect(svg).not.toMatch(/<image\b/);
  });

  it('symbol uses the Fleur-horloge palette', () => {
    const svg = read(join(brandingDir, 'chronoflore-symbol.svg'));
    for (const color of ['#f4b9c8', '#cdc4ef', '#8fcf9f', '#3b3350']) {
      expect(svg.toLowerCase()).toContain(color);
    }
  });

  it('wordmark logos use ink + deep pink and are vector paths', () => {
    for (const name of ['chronoflore-logo-horizontal.svg', 'chronoflore-logo-stacked.svg']) {
      const svg = read(join(brandingDir, name)).toLowerCase();
      expect(svg).toContain('#3b3350');
      expect(svg).toContain('#e48aa3');
      expect(svg).toMatch(/<path\b[^>]*data-wordmark="chrono"/);
      expect(svg).toMatch(/<path\b[^>]*data-wordmark="flore"/);
    }
  });

  it.each([
    ['chronoflore-symbol-mono-ink.svg', '#3b3350'],
    ['chronoflore-symbol-mono-cream.svg', '#fff6e8'],
  ])('%s is single-colour %s', (name, color) => {
    const svg = read(join(brandingDir, name)).toLowerCase();
    const colors = new Set(svg.match(/#[0-9a-f]{6}\b/g));
    // #ffffff / #000000 only appear inside the knockout mask.
    colors.delete('#ffffff');
    colors.delete('#000000');
    expect([...colors]).toEqual([color]);
  });

  it('favicon keeps petals, dial and leaf-hand but drops the thin hand', () => {
    const svg = read(join(repoRoot, 'site/public/favicon.svg'));
    expect(svg).toContain('#8fcf9f');
    expect(svg).not.toContain('data-part="hand"');
  });

  it('game icon is a copy of the symbol and is referenced by project.godot', () => {
    expect(read(join(repoRoot, 'game/icon.svg'))).toBe(read(join(brandingDir, 'chronoflore-symbol.svg')));
    expect(read(join(repoRoot, 'game/project.godot'))).toMatch(/^config\/icon="res:\/\/icon\.svg"$/m);
  });
});

describe('raster exports', () => {
  const pngSize = (file: string) => {
    const buf = readFileSync(file);
    expect(buf.subarray(1, 4).toString('latin1')).toBe('PNG');
    return [buf.readUInt32BE(16), buf.readUInt32BE(20)];
  };

  it.each([
    ['branding/png/chronoflore-symbol-512.png', 512],
    ['branding/png/chronoflore-symbol-1024.png', 1024],
    ['site/public/apple-touch-icon.png', 180],
  ])('%s is %ipx square', (rel, size) => {
    expect(pngSize(join(repoRoot, rel))).toEqual([size, size]);
  });

  it('favicon.ico holds 16, 32 and 48 px images', () => {
    const buf = readFileSync(join(repoRoot, 'site/public/favicon.ico'));
    expect(buf.readUInt16LE(2)).toBe(1); // type: icon
    const count = buf.readUInt16LE(4);
    const sizes = Array.from({ length: count }, (_, i) => buf.readUInt8(6 + i * 16) || 256).sort((a, b) => a - b);
    expect(sizes).toEqual([16, 32, 48]);
  });
});

describe('Logo component', () => {
  it('exposes the leaf-hand hook for the countdown animation', () => {
    const src = read(join(repoRoot, 'site/src/components/Logo.astro'));
    expect(src).toContain('data-logo-hand');
    expect(src).toMatch(/transform-origin/);
  });
});
