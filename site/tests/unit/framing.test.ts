import { describe, expect, it } from 'vitest';
import { ISLAND_SCREEN_RADIUS_M, focusRect, laneWidth, metresPerPixel } from '../../src/scripts/diorama/framing';

const radiusPx = (f: { size: number }) => ISLAND_SCREEN_RADIUS_M / metresPerPixel(f.size);

describe('focusRect', () => {
  it('keeps the hero island right of the hero copy (46vw) on desktop', () => {
    for (const [w, h] of [
      [1024, 768],
      [1280, 800],
      [1440, 900],
      [1920, 1080],
    ]) {
      const f = focusRect(w, h, 0, 0);
      expect(f.x - radiusPx(f), `${w}x${h}`).toBeGreaterThanOrEqual(w * 0.46 + 24);
    }
  });

  it('glides the island into the right-hand lane past the hero', () => {
    for (const [w, h] of [
      [1024, 768],
      [1440, 900],
      [2560, 1440],
    ]) {
      const f = focusRect(w, h, 1, 1);
      expect(f.x - radiusPx(f), `${w}x${h}`).toBeGreaterThanOrEqual(w - laneWidth(w));
      expect(f.x + radiusPx(f)).toBeLessThanOrEqual(w);
      expect(f.size).toBeLessThan(focusRect(w, h, 0, 0).size);
    }
  });

  it('matches the CSS lane: clamp(16rem, 24vw, 22rem)', () => {
    expect(laneWidth(800)).toBe(256);
    expect(laneWidth(1200)).toBe(288);
    expect(laneWidth(2000)).toBe(352);
  });

  it('ignores the glide on small screens (the stage scrolls away with the hero)', () => {
    expect(focusRect(390, 844, 0.5, 1)).toEqual(focusRect(390, 844, 0.5, 0));
  });
});
