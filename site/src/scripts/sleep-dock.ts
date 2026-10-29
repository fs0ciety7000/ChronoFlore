// Docked mini sleep clock (SleepDock.astro): shown once the countdown band has
// scrolled above the viewport, hidden again when it comes back. The digits
// follow the same sleepClockAt as #countdown; the leaf-hand is turned by
// clock-hand.ts with every other animated hand.
//
// Not an IntersectionObserver: a jump from the top straight past the band
// (anchor link, Home/End) never intersects it, so no entry would fire. The
// band's bottom edge is cached and re-measured only when the layout resizes,
// so the scroll callback reads no layout after scroll.ts writes its CSS vars.
import type { ScrollHandle } from './scroll';
import { sleepClockAt } from './timeline';

export function initSleepDock(scroll: Pick<ScrollHandle, 'onProgress'>): void {
  const dock = document.querySelector<HTMLElement>('[data-sleep-dock]');
  const time = dock?.querySelector<HTMLElement>('[data-sleep-dock-time]');
  const band = document.querySelector<HTMLElement>('[data-scene="countdown"]');
  if (!dock || !time || !band) return;

  let bandBottom = 0;
  const measure = () => {
    bandBottom = band.getBoundingClientRect().bottom + window.scrollY;
  };
  measure();

  let last = '';
  let docked = false;
  const update = (p: number) => {
    const clock = sleepClockAt(p);
    if (clock !== last) time.textContent = last = clock;
    const next = window.scrollY > bandBottom;
    if (next !== docked) dock.classList.toggle('is-docked', (docked = next));
  };
  let progress = 0;
  scroll.onProgress((p) => update((progress = p)));

  if ('ResizeObserver' in window) {
    new ResizeObserver(() => {
      measure();
      update(progress);
    }).observe(document.body);
  }
}
