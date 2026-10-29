import { describe, expect, it } from 'vitest';
import {
  PALETTES,
  clampProgress,
  countdownAt,
  dawnFactor,
  mutedTones,
  nightFactor,
  paletteAt,
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

describe('countdownAt', () => {
  it('formats HH:MM:SS from 2h', () => {
    expect(countdownAt(0)).toBe('02:00:00');
    expect(countdownAt(1)).toBe('00:00:00');
    expect(countdownAt(0.5)).toBe('01:00:00');
    expect(countdownAt(-3)).toBe('02:00:00');
    expect(countdownAt(NaN)).toBe('02:00:00');
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
