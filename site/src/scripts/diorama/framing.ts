// Where the island sits on screen. Pure maths shared by scene.ts and the unit
// tests; the CSS twins live in Hero.astro (--focus-*) and global.css (--lane).

/** Breakpoint (CSS px) of the desktop layout: 56rem. */
export const DESKTOP_MIN = 896;
/** Metres of scene shown across `size` pixels: the island (24 m) plus air. */
export const FRAME_METRES = 31;
/** Island half-width on screen in metres: 12 m radius plus canopy overhang. */
export const ISLAND_SCREEN_RADIUS_M = 13;

/** Right-hand lane kept free of copy past the hero: clamp(16rem, 24vw, 22rem). */
export function laneWidth(w: number): number {
  return Math.min(352, Math.max(256, w * 0.24));
}

export function metresPerPixel(size: number): number {
  return FRAME_METRES / size;
}

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

export type Focus = { x: number; y: number; size: number };

/**
 * Focus point (canvas CSS px) and framing size of the island.
 * `dive` 0..1 follows the scroll; `glide` 0..1 moves it from the hero
 * composition into the right-hand lane (desktop only: on small screens the
 * stage scrolls away with the hero instead).
 */
export function focusRect(w: number, h: number, dive: number, glide: number): Focus {
  if (w < DESKTOP_MIN) {
    const size = Math.min(w * 0.98, h * 0.52);
    return { x: w * 0.5, y: h * lerp(0.3, 0.34, dive), size };
  }
  const hero = { x: w * 0.72, y: h * 0.54, size: Math.min(w * 0.5, h * 0.95) };
  const lane = laneWidth(w);
  // Fit the island inside the lane with an 8 px margin on each side.
  const cornerSize = ((lane / 2 - 8) * FRAME_METRES) / ISLAND_SCREEN_RADIUS_M;
  const corner = { x: w - lane / 2, y: h * 0.56, size: Math.min(cornerSize, h * 0.6) };
  const g = glide * glide * (3 - 2 * glide);
  return { x: lerp(hero.x, corner.x, g), y: lerp(hero.y, corner.y, g), size: lerp(hero.size, corner.size, g) };
}
