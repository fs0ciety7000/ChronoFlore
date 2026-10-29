import { mixHex } from './color';
import { paletteFor } from './timeline';

/** Light rig of the diorama for a night factor and a dawn factor (both 0..1). */
export type Light = {
  background: string;
  hemiSky: string;
  hemiGround: string;
  hemiIntensity: number;
  sunColor: string;
  sunIntensity: number;
  sunElevationDeg: number;
  /** 0..1: how much the flowers and fireflies glow. */
  glow: number;
};

type Rig = Omit<Light, 'background' | 'glow'>;

// Soft pastel day, a cool moonlit night and a pink dawn. Polyfork colours are
// authored for NoToneMapping at around these intensities.
const DAY: Rig = {
  hemiSky: '#fff6ea',
  hemiGround: '#c9b49b',
  hemiIntensity: 1.9,
  sunColor: '#fff0dc',
  sunIntensity: 2.1,
  sunElevationDeg: 52,
};
// Golden hour, passed through on the way to night (spec: jour -> doré -> crépuscule).
const GOLDEN: Rig = {
  hemiSky: '#ffe0bd',
  hemiGround: '#b9927a',
  hemiIntensity: 1.6,
  sunColor: '#ffc38a',
  sunIntensity: 2.2,
  sunElevationDeg: 30,
};
const GOLDEN_AT = 0.35;
const NIGHT: Rig = {
  hemiSky: '#8d88d6',
  hemiGround: '#2c2850',
  hemiIntensity: 0.85,
  sunColor: '#b4bcff', // moonlight
  sunIntensity: 0.55,
  sunElevationDeg: 14,
};
const DAWN: Rig = {
  hemiSky: '#ffe2e6',
  hemiGround: '#d7b2a8',
  hemiIntensity: 1.7,
  sunColor: '#ffc9b2',
  sunIntensity: 1.8,
  sunElevationDeg: 20,
};

const clamp01 = (x: number) => (Number.isFinite(x) ? Math.min(1, Math.max(0, x)) : 0);
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

export function lightAt(night: number, dawn: number): Light {
  const n = clamp01(night);
  const d = clamp01(dawn);
  // Day -> golden -> night along n, then toward dawn along d.
  const [from, to, t] = n < GOLDEN_AT ? [DAY, GOLDEN, n / GOLDEN_AT] : [GOLDEN, NIGHT, (n - GOLDEN_AT) / (1 - GOLDEN_AT)];
  const color = (key: 'hemiSky' | 'hemiGround' | 'sunColor') => mixHex(mixHex(from[key], to[key], t), DAWN[key], d);
  const num = (key: 'hemiIntensity' | 'sunIntensity' | 'sunElevationDeg') => lerp(lerp(from[key], to[key], t), DAWN[key], d);
  return {
    background: paletteFor(n, d).bg,
    hemiSky: color('hemiSky'),
    hemiGround: color('hemiGround'),
    hemiIntensity: num('hemiIntensity'),
    sunColor: color('sunColor'),
    sunIntensity: num('sunIntensity'),
    sunElevationDeg: num('sunElevationDeg'),
    glow: n * (1 - d),
  };
}
