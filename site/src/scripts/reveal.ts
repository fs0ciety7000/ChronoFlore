// Scroll reveals: titles and cards marked [data-reveal] rise 16px and fade in
// once, 500ms, in a 60ms cascade (CSS in global.css). Nothing is hidden until
// this runs and adds html.reveal-on, so without JS (or with reduced motion,
// where it never runs) everything is simply visible.
import type { Env } from './env';

export const REVEAL_STAGGER_MS = 60;
/** Cascade cap: a long batch should not keep the last item waiting. */
const MAX_STEPS = 5;

/** Delay for the i-th item revealed in the same batch. */
export function revealDelay(index: number): number {
  return Math.min(index, MAX_STEPS) * REVEAL_STAGGER_MS;
}

export function initReveal(env: Env): void {
  if (env.reducedMotion || !('IntersectionObserver' in window)) return;
  const items = [...document.querySelectorAll<HTMLElement>('[data-reveal]')];
  if (!items.length) return;

  // Whatever is already on screen (or scrolled past) stays as it is: no flash.
  // All reads first, then all writes, so layout is computed once.
  const tops = items.map((el) => el.getBoundingClientRect().top);
  const pending = items.filter((_, i) => tops[i] >= innerHeight);
  items.forEach((el, i) => {
    if (tops[i] < innerHeight) el.classList.add('is-revealed');
  });
  document.documentElement.classList.add('reveal-on');

  const io = new IntersectionObserver(
    (entries) => {
      // Entries arrive in DOM order; those landing together form one cascade.
      entries
        .filter((e) => e.isIntersecting)
        .forEach((e, i) => {
          const el = e.target as HTMLElement;
          io.unobserve(el);
          const delay = revealDelay(i);
          if (delay) el.style.transitionDelay = `${delay}ms`;
          // .is-revealing carries the reveal transition only while it plays;
          // afterwards the element's own transitions apply untouched.
          const done = (t: TransitionEvent) => {
            if (t.target !== el || t.propertyName !== 'transform') return;
            el.removeEventListener('transitionend', done);
            el.classList.remove('is-revealing');
            el.style.removeProperty('transition-delay');
          };
          el.addEventListener('transitionend', done);
          el.classList.add('is-revealing', 'is-revealed');
        });
    },
    // Trigger a little before the element is fully in, so it is moving as it lands.
    { rootMargin: '0px 0px -8% 0px' },
  );
  pending.forEach((el) => io.observe(el));
}
