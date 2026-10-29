// The leaf-hands of the sleep-clock logos (Countdown.astro, SleepDock.astro)
// turn with the page:
// one full turn from 00:00:00 to 08:00:00, so 180deg at 50 % progress. Its
// pivot (dial centre) is set in Logo.astro. Scroll-linked, so it stays on with
// reduced motion: like the digits, it is the clock's state, not decoration.
import type { ScrollHandle } from './scroll';

export function handRotation(progress: number): string {
  const p = Math.min(1, Math.max(0, progress));
  return `rotate(${+(p * 360).toFixed(2)}deg)`;
}

export function initClockHand(scroll: Pick<ScrollHandle, 'onProgress'>): void {
  const hands = document.querySelectorAll<SVGElement>('[data-animated-hand] [data-logo-hand]');
  if (!hands.length) return;
  scroll.onProgress((p) => {
    const rotation = handRotation(p);
    hands.forEach((hand) => (hand.style.transform = rotation));
  });
}
