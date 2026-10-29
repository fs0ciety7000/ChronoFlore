// Starts the live diorama once the page is idle. Kept tiny: three.js and the
// scene live in the scene.ts chunk, imported only when the device can take it.
import { shouldUse3D, type Env } from '../env';
import type { ScrollHandle } from '../scroll';

type Progress = Pick<ScrollHandle, 'onProgress'>;

function whenIdle(cb: () => void) {
  const idle = () => {
    if ('requestIdleCallback' in window) requestIdleCallback(cb, { timeout: 3000 });
    else setTimeout(cb, 1000);
  };
  // Let the poster and fonts finish first: the 3D is an enhancement.
  if (document.readyState === 'complete') idle();
  else window.addEventListener('load', idle, { once: true });
}

export function mountDiorama(env: Env, scroll?: Progress): void {
  if (!shouldUse3D(env)) return;
  const host = document.getElementById('diorama');
  if (!host) return;
  // Reserve the right-hand lane for the island past the hero (desktop CSS in
  // global.css). Set now, before the sections below the fold are seen.
  const root = document.documentElement;
  root.classList.add('has-diorama');

  whenIdle(async () => {
    const canvas = document.createElement('canvas');
    canvas.className = 'diorama__canvas';
    canvas.setAttribute('aria-hidden', 'true');
    const cleanups: (() => void)[] = [];
    let diorama: import('./scene').Diorama | undefined;
    let failed = false;

    // Any failure leaves the poster in place; the page never depends on 3D.
    const fail = (e?: unknown) => {
      if (failed) return;
      failed = true;
      host.dataset.state = 'poster';
      root.classList.remove('has-diorama');
      cleanups.forEach((c) => c());
      diorama?.dispose();
      canvas.remove();
      if (e) console.warn('[diorama] staying on the poster:', e);
    };

    canvas.addEventListener('webglcontextlost', () => fail(), { once: true });
    host.append(canvas);

    try {
      const { createDiorama } = await import('./scene');
      if (failed) return;
      diorama = createDiorama(canvas, {
        onReady: () => {
          if (!failed) host.dataset.state = 'live';
        },
        onError: fail,
      });
    } catch (e) {
      fail(e);
      return;
    }

    const d = diorama;
    // Glide: 0 at the top, 1 once most of the hero has scrolled past.
    const hero = document.getElementById('top');
    const glide = () => (hero ? Math.min(1, Math.max(0, window.scrollY / (hero.offsetHeight * 0.85))) : 1);
    if (scroll) {
      cleanups.push(
        scroll.onProgress((p) => {
          d.setProgress(p);
          d.setGlide(glide());
        }),
      );
    }
    const onPointer = (e: PointerEvent) => {
      if (e.pointerType === 'touch') return;
      d.setPointer((e.clientX / window.innerWidth) * 2 - 1, (e.clientY / window.innerHeight) * 2 - 1);
    };
    window.addEventListener('pointermove', onPointer, { passive: true });
    cleanups.push(() => window.removeEventListener('pointermove', onPointer));
  });
}
