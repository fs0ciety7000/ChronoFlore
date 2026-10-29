import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import Lenis from 'lenis';
import type { Env } from './env';
import { PALETTES, clampProgress, countdownAt, mutedTones, paletteAt, type Palette } from './timeline';

export type ScrollHandle = {
  onProgress(cb: (p: number) => void): () => void;
  destroy(): void;
};

// Reduced motion: three discrete states cross-faded by CSS instead of a
// continuous palette (see the reduced-motion block in global.css).
function discretePalette(p: number): Palette {
  if (p < 0.3) return PALETTES.day;
  return p < 0.85 ? PALETTES.night : PALETTES.dawn;
}

export function initScroll(env: Env): ScrollHandle {
  gsap.registerPlugin(ScrollTrigger);

  const root = document.documentElement;
  const countdown = document.getElementById('countdown');
  const listeners = new Set<(p: number) => void>();
  let lastClock = '';

  const apply = (raw: number) => {
    const p = clampProgress(raw);
    const palette = env.reducedMotion ? discretePalette(p) : paletteAt(p);
    root.style.setProperty('--bg', palette.bg);
    root.style.setProperty('--ink', palette.ink);
    root.style.setProperty('--accent', palette.accent);
    root.style.setProperty('--surface', palette.surface);
    // Inline values override the day-time colour-mix fallbacks in tokens.css.
    const tones = mutedTones(palette);
    root.style.setProperty('--ink-soft', tones.inkSoft);
    root.style.setProperty('--caption', tones.caption);
    root.style.setProperty('--progress', String(+p.toFixed(4)));
    const clock = countdownAt(p);
    if (countdown && clock !== lastClock) {
      countdown.textContent = clock;
      lastClock = clock;
    }
    listeners.forEach((cb) => cb(p));
  };

  // progress = scrollY / (scrollHeight - innerHeight); ScrollTrigger recomputes
  // the range on resize/refresh, and onRefresh re-applies it so a clamped scroll
  // position after a resize still lands on the right palette.
  const trigger = ScrollTrigger.create({
    trigger: root,
    start: 0,
    end: 'max',
    onUpdate: (self) => apply(self.progress),
    onRefresh: (self) => apply(self.progress),
  });
  apply(trigger.progress);

  let lenis: Lenis | undefined;
  let tick: ((time: number) => void) | undefined;
  if (env.finePointer && !env.reducedMotion) {
    lenis = new Lenis();
    lenis.on('scroll', ScrollTrigger.update);
    tick = (time) => lenis!.raf(time * 1000);
    gsap.ticker.add(tick);
    gsap.ticker.lagSmoothing(0);
  }

  return {
    onProgress(cb) {
      listeners.add(cb);
      cb(trigger.progress);
      return () => listeners.delete(cb);
    },
    destroy() {
      if (tick) gsap.ticker.remove(tick);
      lenis?.destroy();
      trigger.kill();
      listeners.clear();
    },
  };
}
