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
  return paletteFor(nightFactor(p), dawnFactor(p));
}

/**
 * Dusk keyframes between day and night. A straight RGB mix of cream and
 * indigo passes through a flat grey; going through a golden hour and a rose
 * twilight keeps the sky pastel and chromatic all the way (ink and tones are
 * still derived from bg below, so the contrast rules are unchanged).
 */
const DUSK: { at: number; palette: Omit<Palette, 'ink'> }[] = [
  { at: 0.35, palette: { bg: '#f6dcc0', accent: '#f4b0bc', surface: '#fff7ee' } },
  { at: 0.65, palette: { bg: '#c4899c', accent: '#f7c0cf', surface: '#f8e9ec' } },
];

/** Day -> golden -> twilight -> night along `n` (0..1), for one palette key. */
function nightMix(key: 'bg' | 'accent' | 'surface', n: number): string {
  const stops = [
    { at: 0, color: PALETTES.day[key] },
    ...DUSK.map((k) => ({ at: k.at, color: k.palette[key] })),
    { at: 1, color: PALETTES.night[key] },
  ];
  const t = Math.min(1, Math.max(0, Number.isFinite(n) ? n : 0));
  let i = 0;
  while (i < stops.length - 2 && t > stops[i + 1].at) i++;
  const a = stops[i];
  const b = stops[i + 1];
  return mixHex(a.color, b.color, (t - a.at) / (b.at - a.at));
}

// Sunrise, halfway from night to dawn, for the same reason (no grey).
const SUNRISE: Omit<Palette, 'ink'> = { bg: '#cf8fa6', accent: '#f6bccb', surface: '#f9e8ec' };

/** Palette for a night factor `n` and a dawn factor `d` (both 0..1). */
export function paletteFor(n: number, d: number): Palette {
  const { night, dawn, day } = PALETTES;
  const dd = Math.min(1, Math.max(0, Number.isFinite(d) ? d : 0));
  const mix = (key: 'bg' | 'accent' | 'surface') => {
    const from = nightMix(key, n);
    return dd < 0.5 ? mixHex(from, SUNRISE[key], dd / 0.5) : mixHex(SUNRISE[key], dawn[key], (dd - 0.5) / 0.5);
  };
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
