import { mixHex } from '../../src/scripts/color';
import { describe, expect, it } from 'vitest';
import {
  PALETTES,
  clampProgress,
  sleepClockAt,
  dawnFactor,
  mutedTones,
  nightFactor,
  paletteAt,
  paletteFor,
  surfaceTones,
} from '../../src/scripts/timeline';

function luminance(hex: string): number {
  const c = [1, 3, 5].map((i) => {
    const v = parseInt(hex.slice(i, i + 2), 16) / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}
function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

describe('clampProgress', () => {
  it('clamps and handles NaN', () => {
    expect(clampProgress(NaN)).toBe(0);
    expect(clampProgress(-3)).toBe(0);
    expect(clampProgress(4)).toBe(1);
    expect(clampProgress(0.3)).toBe(0.3);
  });
});

describe('sleepClockAt', () => {
  it('counts up HH:MM:SS to 8h', () => {
    expect(sleepClockAt(0)).toBe('00:00:00');
    expect(sleepClockAt(1)).toBe('08:00:00');
    expect(sleepClockAt(0.5)).toBe('04:00:00');
    expect(sleepClockAt(-3)).toBe('00:00:00');
    expect(sleepClockAt(NaN)).toBe('00:00:00');
  });
});

describe('factors', () => {
  it('hit their bounds', () => {
    expect(nightFactor(0.08)).toBe(0);
    expect(nightFactor(0.75)).toBe(1);
    expect(dawnFactor(0.82)).toBe(0);
    expect(dawnFactor(0.97)).toBe(1);
  });
});

describe('paletteAt', () => {
  it('matches day, night and dawn at the anchors', () => {
    expect(paletteAt(0)).toEqual(PALETTES.day);
    expect(paletteAt(0.78).bg).toBe(PALETTES.night.bg);
    expect(paletteAt(1)).toEqual(PALETTES.dawn);
  });
  it('keeps ink/bg contrast >= 4.5 for every progress', () => {
    for (let i = 0; i <= 100; i++) {
      const p = paletteAt(i / 100);
      expect(contrast(p.ink, p.bg), `p=${i / 100}`).toBeGreaterThanOrEqual(4.5);
    }
  });
});

describe('mutedTones', () => {
  it('keeps both muted tones at >= 4.5:1 for every progress', () => {
    for (let i = 0; i <= 1000; i++) {
      const palette = paletteAt(i / 1000);
      const { inkSoft, caption } = mutedTones(palette);
      expect(contrast(inkSoft, palette.bg), `inkSoft ${i / 1000}`).toBeGreaterThanOrEqual(4.5);
      expect(contrast(caption, palette.bg), `caption ${i / 1000}`).toBeGreaterThanOrEqual(4.5);
    }
  });
});

describe('surfaceTones', () => {
  it('keeps text on --ink and on --surface readable at every progress', () => {
    for (let i = 0; i <= 1000; i++) {
      const palette = paletteAt(i / 1000);
      const { onInk, onSurface, onField } = surfaceTones(palette);
      expect(contrast(onField, mixHex(palette.surface, '#cdc4ef', 0.32)), `onField at ${i / 1000}`).toBeGreaterThanOrEqual(4.5);
      expect(contrast(onInk, palette.ink), `onInk at ${i / 1000}`).toBeGreaterThanOrEqual(4.5);
      expect(contrast(onSurface, palette.surface), `onSurface at ${i / 1000}`).toBeGreaterThanOrEqual(4.5);
    }
  });
  it('is the plain surface/ink pairing at the design endpoints', () => {
    expect(surfaceTones(PALETTES.day)).toMatchObject({ onInk: PALETTES.day.surface, onSurface: PALETTES.day.ink });
    expect(surfaceTones(PALETTES.night)).toMatchObject({ onInk: PALETTES.night.surface, onSurface: PALETTES.night.ink });
  });
});

describe('paletteFor', () => {
  it('is what paletteAt uses for the night and dawn factors', () => {
    for (const p of [0, 0.1, 0.3, 0.42, 0.5, 0.75, 0.85, 0.9, 1]) {
      expect(paletteFor(nightFactor(p), dawnFactor(p))).toEqual(paletteAt(p));
    }
  });

  it('gives the three reference palettes at the extremes', () => {
    expect(paletteFor(0, 0).bg).toBe(PALETTES.day.bg);
    expect(paletteFor(1, 0).bg).toBe(PALETTES.night.bg);
    expect(paletteFor(1, 1).bg).toBe(PALETTES.dawn.bg);
  });
});

/** OKLCH chroma of a #rrggbb colour. */
function chroma(hex: string): number {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const v = parseInt(hex.slice(i, i + 2), 16) / 255;
    return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  const A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
  const B = 0.0259040371 * l + 0.7827717662 * m - 0.808497678 * s;
  return Math.hypot(A, B);
}

describe('day to night transition', () => {
  it('stays chromatic (never passes through grey)', () => {
    const floor = Math.min(chroma(PALETTES.day.bg), chroma(PALETTES.night.bg));
    for (let i = 0; i <= 1000; i++) {
      const { bg } = paletteAt(i / 1000);
      expect(chroma(bg), `bg ${bg} at ${i / 1000}`).toBeGreaterThanOrEqual(floor * 0.95);
    }
  });
});
