// Live 3D portraits of the heroine and the companion (Planches II and III).
// Kept tiny for the initial bundle: three.js and the portrait scene load
// (with the diorama's 3D chunk) only once a portrait card nears the viewport.
// Without 3D the cards keep their still image (rendered from the same models
// by scripts/render-poster.mjs).
import { shouldUse3D, type Env } from '../env';
import { whenIdle } from '../diorama/loader';

export function mountPortraits(env: Env): void {
  const cards = [...document.querySelectorAll<HTMLElement>('[data-portrait]')];
  if (!cards.length || !('IntersectionObserver' in window) || !shouldUse3D(env)) return;

  whenIdle(() => {
    const near = new IntersectionObserver(
      (entries) => {
        if (!entries.some((e) => e.isIntersecting)) return;
        near.disconnect();
        start(cards);
      },
      { rootMargin: '75% 0px' },
    );
    cards.forEach((c) => near.observe(c));
  });
}

async function start(cards: HTMLElement[]) {
  let failed = false;
  let portraits: import('./scene').Portraits | undefined;
  // Any failure leaves (or puts back) the still images.
  const fail = (e?: unknown) => {
    if (failed) return;
    failed = true;
    portraits?.dispose();
    for (const card of cards) {
      card.dataset.state = 'still';
      card.removeAttribute('tabindex');
      card.removeAttribute('data-playing');
      card.removeAttribute('data-action');
      card.querySelector('canvas')?.remove();
    }
    if (e) console.warn('[portraits] staying on the still images:', e);
  };
  try {
    const { createPortraits } = await import('./scene');
    portraits = createPortraits(cards, { onError: fail });
  } catch (e) {
    fail(e);
  }
}
