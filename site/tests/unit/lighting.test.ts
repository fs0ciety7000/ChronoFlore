import { describe, expect, it } from 'vitest';
import { lightAt } from '../../src/scripts/lighting';
import { dawnFactor, nightFactor, paletteAt } from '../../src/scripts/timeline';

describe('lightAt', () => {
  it('uses the page background as the scene background', () => {
    expect(lightAt(0, 0).background).toBe('#f6f1e7');
    expect(lightAt(1, 0).background).toBe('#22203a');
    expect(lightAt(1, 1).background).toBe('#fbeee9');
    for (const p of [0.2, 0.45, 0.6, 0.9]) {
      expect(lightAt(nightFactor(p), dawnFactor(p)).background).toBe(paletteAt(p).bg);
    }
  });

  it('glows only at night', () => {
    expect(lightAt(0, 0).glow).toBe(0);
    expect(lightAt(1, 0).glow).toBe(1);
    expect(lightAt(1, 1).glow).toBe(0);
    expect(lightAt(0.5, 0.5).glow).toBeCloseTo(0.25);
  });

  it('lowers the sun from day to night', () => {
    let last = Infinity;
    for (const n of [0, 0.25, 0.5, 0.75, 1]) {
      const { sunElevationDeg } = lightAt(n, 0);
      expect(sunElevationDeg).toBeLessThan(last);
      last = sunElevationDeg;
    }
  });

  it('dims the lights at night', () => {
    expect(lightAt(1, 0).sunIntensity).toBeLessThan(lightAt(0, 0).sunIntensity);
    expect(lightAt(1, 0).hemiIntensity).toBeLessThan(lightAt(0, 0).hemiIntensity);
    for (const key of ['hemiSky', 'hemiGround', 'sunColor'] as const) {
      expect(lightAt(0.3, 0.2)[key]).toMatch(/^#[0-9a-f]{6}$/);
    }
  });
});
