// Custom cursor: a small butterfly net that tracks a fine pointer 1:1 (no lag,
// no easing on position). Off on touch and with reduced motion. The system
// cursor comes back over text fields; links and buttons tilt the net.
import type { Env } from './env';

/** Hoop centre inside the 32x32 graphic: the hotspot sits on the pointer. */
export const HOTSPOT = { x: 12, y: 12 } as const;

const ACTION = 'a[href], button, [role="button"], label, summary, select';
const TEXT_FIELD = 'input:not([type="button"],[type="submit"],[type="reset"],[type="checkbox"],[type="radio"],[type="range"],[type="color"],[type="file"]), textarea, [contenteditable=""], [contenteditable="true"]';

const NET_SVG = `<svg viewBox="0 0 32 32" width="32" height="32" fill="none" stroke-linecap="round" stroke-linejoin="round">
  <g class="cursor-net__halo" stroke-width="4.2"><circle cx="12" cy="12" r="8"/><path d="M18 18 L28 28"/></g>
  <g class="cursor-net__line" stroke-width="1.7">
    <circle cx="12" cy="12" r="8"/><path d="M18 18 L28 28"/>
    <path d="M8.5 5.5 V18.5 M12 4 V20 M15.5 5.5 V18.5 M5.5 8.5 H18.5 M4 12 H20 M5.5 15.5 H18.5" stroke-width="0.9" opacity="0.7"/>
  </g>
  <circle data-hotspot cx="12" cy="12" r="1.4" class="cursor-net__dot"/>
</svg>`;

export function initCursor(env: Env): void {
  if (!env.finePointer || env.reducedMotion) return;

  const root = document.documentElement;
  const el = document.createElement('div');
  el.className = 'cursor-net';
  el.setAttribute('aria-hidden', 'true');
  el.innerHTML = `<div class="cursor-net__body">${NET_SVG}</div>`;
  document.body.append(el);


  const setState = (name: string, on: boolean) => el.classList.toggle(name, on);
  // The system cursor hides only while the net is on screen.
  const show = (on: boolean) => {
    setState('is-visible', on);
    root.classList.toggle('has-cursor-net', on);
  };

  window.addEventListener(
    'pointermove',
    (e) => {
      // A pen or a finger on a hybrid device: let the system handle it.
      if (e.pointerType !== 'mouse') {
        show(false);
        return;
      }
      // Written straight away: browsers already align pointermove to frames,
      // and a rAF hop would leave the net one frame behind on first show.
      el.style.transform = `translate3d(${e.clientX - HOTSPOT.x}px, ${e.clientY - HOTSPOT.y}px, 0)`;
      show(true);
      const target = e.target instanceof Element ? e.target : null;
      setState('is-over-text', !!target?.closest(TEXT_FIELD));
      setState('is-over-action', !!target?.closest(ACTION));
    },
    { passive: true },
  );
  // Leaving the window (relatedTarget null) hides the net until it comes back.
  document.addEventListener('pointerout', (e) => {
    if (!e.relatedTarget) show(false);
  });
  window.addEventListener('pointerdown', () => setState('is-pressed', true), { passive: true });
  window.addEventListener('pointerup', () => setState('is-pressed', false), { passive: true });
  window.addEventListener('blur', () => {
    show(false);
    setState('is-pressed', false); // the pointerup may land in another window
  });
}
