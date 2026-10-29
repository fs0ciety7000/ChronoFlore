// The leaf-hand of the sleep-clock logo (Countdown.astro) turns with the page:
// one full turn from 00:00:00 to 08:00:00, so 180deg at 50 % progress. Its
// pivot (dial centre) is set in Logo.astro. Scroll-linked, so it stays on with
// reduced motion: like the digits, it is the clock's state, not decoration.
import type { ScrollHandle } from './scroll';

export function handRotation(progress: number): string {
  const p = Math.min(1, Math.max(0, progress));
  return `rotate(${+(p * 360).toFixed(2)}deg)`;
}

export function initClockHand(scroll: Pick<ScrollHandle, 'onProgress'>): void {
  const hand = document.querySelector<SVGElement>('[data-animated-hand] [data-logo-hand]');
  if (!hand) return;
  scroll.onProgress((p) => {
    hand.style.transform = handRotation(p);
  });
}
