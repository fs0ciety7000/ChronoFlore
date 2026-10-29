import { contrast, luminance, mixHex } from './color';

export type Palette = { bg: string; ink: string; accent: string; surface: string };

export const PALETTES: { day: Palette; night: Palette; dawn: Palette } = {
  day: { bg: '#f6f1e7', ink: '#3b3350', accent: '#f4b9c8', surface: '#fffdf8' },
  night: { bg: '#22203a', ink: '#ede8fb', accent: '#f7c3d2', surface: '#2d2a4c' },
  dawn: { bg: '#fbeee9', ink: '#3b3350', accent: '#f4b9c8', surface: '#fffdf8' },
};

const TOTAL_SECONDS = 28800;
const MIN_CONTRAST = 4.5;
const CROSSOVER_LUMINANCE = 0.179; // sqrt(1.05 * 0.05) - 0.05

export function clampProgress(p: number): number {
  if (!Number.isFinite(p)) return 0;
  return Math.min(1, Math.max(0, p));
}

function smoothstep(edge0: number, edge1: number, x: number): number {
  const t = Math.min(1, Math.max(0, (x - edge0) / (edge1 - edge0)));
  return t * t * (3 - 2 * t);
}

export function nightFactor(p: number): number {
  return smoothstep(0.08, 0.75, clampProgress(p));
}

export function dawnFactor(p: number): number {
  return smoothstep(0.82, 0.97, clampProgress(p));
}

export function paletteAt(p: number): Palette {
  const n = nightFactor(p);
  const d = dawnFactor(p);
  const { day, night, dawn } = PALETTES;
  const mix = (key: keyof Palette) => mixHex(mixHex(day[key], night[key], n), dawn[key], d);
  const bg = mix('bg');
  // Ink flips (not interpolated) between the day and night inks at the
  // luminance where white and black give equal contrast (~0.179). Near that
  // crossover neither endpoint ink reaches 4.5:1, so it is pushed toward pure
  // black/white just enough to get there.
  const useLight = luminance(bg) < CROSSOVER_LUMINANCE;
  const base = useLight ? night.ink : day.ink;
  const extreme = useLight ? '#ffffff' : '#000000';
  let ink = base;
  for (let t = 0; t <= 1 && contrast(ink, bg) < MIN_CONTRAST; t += 0.05) {
    ink = mixHex(base, extreme, t);
  }
  return { bg, ink, accent: mix('accent'), surface: mix('surface') };
}

/** Elapsed time of the 8h night as `HH:MM:SS` (counts up). */
export function sleepClockAt(p: number): string {
  const elapsed = Math.round(TOTAL_SECONDS * clampProgress(p));
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${pad(Math.floor(elapsed / 3600))}:${pad(Math.floor((elapsed % 3600) / 60))}:${pad(elapsed % 60)}`;
}

/**
 * Muted text tones derived from a palette. A fixed colour-mix cannot hold 4.5:1
 * near the day/night crossover (the ink itself only just reaches it there), so
 * each tone starts at its design weight and moves back toward the ink until it
 * is readable on the background.
 */
export function mutedTones(palette: Palette): { inkSoft: string; caption: string } {
  const { bg, ink, accent } = palette;
  const readable = (tone: (t: number) => string, from: number) => {
    let color = tone(from);
    for (let t = from; t >= 0 && contrast(color, bg) < MIN_CONTRAST; t -= 0.04) color = tone(Math.max(0, t));
    return contrast(color, bg) >= MIN_CONTRAST ? color : ink;
  };
  return {
    inkSoft: readable((t) => mixHex(bg, ink, 1 - t), 0.24), // 76% ink at best
    caption: readable((t) => mixHex(ink, accent, t), 0.32),
  };
}

/**
 * Text colours for the two pairings that do not sit on `--bg`: text on the
 * `--ink` fill (primary buttons) and text on the `--surface` fill (cards) and on the `--field` fill (soft buttons).
 * `--surface` is mixed continuously while `--ink` flips, so near the crossover
 * the plain pairings can fall under 4.5:1. Each tone starts at its design
 * colour and is pushed toward black/white only as far as needed.
 */
export const LAVENDER = '#cdc4ef'; // --lavender in tokens.css

export function surfaceTones(palette: Palette): { onInk: string; onSurface: string; onField: string } {
  const { ink, surface } = palette;
  const readable = (start: string, on: string) => {
    if (contrast(start, on) >= MIN_CONTRAST) return start;
    const extreme = luminance(on) < CROSSOVER_LUMINANCE ? '#ffffff' : '#000000';
    let color = start;
    for (let i = 1; i <= 20 && contrast(color, on) < MIN_CONTRAST; i++) {
      color = mixHex(start, extreme, i / 20);
    }
    return color;
  };
  // --field = color-mix(in srgb, surface 68%, lavender)
  const field = mixHex(surface, LAVENDER, 0.32);
  return { onInk: readable(surface, ink), onSurface: readable(ink, surface), onField: readable(ink, field) };
}
