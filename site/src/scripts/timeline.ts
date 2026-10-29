import { contrast, luminance, mixHex } from './color';

export type Palette = { bg: string; ink: string; accent: string; surface: string };

export const PALETTES: { day: Palette; night: Palette; dawn: Palette } = {
  day: { bg: '#f6f1e7', ink: '#3b3350', accent: '#f4b9c8', surface: '#fffdf8' },
  night: { bg: '#22203a', ink: '#ede8fb', accent: '#f7c3d2', surface: '#2d2a4c' },
  dawn: { bg: '#fbeee9', ink: '#3b3350', accent: '#f4b9c8', surface: '#fffdf8' },
};

const TOTAL_SECONDS = 7200;
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

/** Remaining time of the 2h night as `HH:MM:SS`. */
export function countdownAt(p: number): string {
  const left = Math.round(TOTAL_SECONDS * (1 - clampProgress(p)));
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${pad(Math.floor(left / 3600))}:${pad(Math.floor((left % 3600) / 60))}:${pad(left % 60)}`;
}
