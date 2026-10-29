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

  whenIdle(async () => {
    const canvas = document.createElement('canvas');
    canvas.className = 'diorama__canvas';
    canvas.setAttribute('aria-hidden', 'true');
    const cleanups: (() => void)[] = [];
    let diorama: { setProgress(p: number): void; setPointer(nx: number, ny: number): void; dispose(): void } | undefined;
    let failed = false;

    // Any failure leaves the poster in place; the page never depends on 3D.
    const fail = (e?: unknown) => {
      if (failed) return;
      failed = true;
      host.dataset.state = 'poster';
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
    if (scroll) cleanups.push(scroll.onProgress((p) => d.setProgress(p)));
    const onPointer = (e: PointerEvent) => {
      if (e.pointerType === 'touch') return;
      d.setPointer((e.clientX / window.innerWidth) * 2 - 1, (e.clientY / window.innerHeight) * 2 - 1);
    };
    window.addEventListener('pointermove', onPointer, { passive: true });
    cleanups.push(() => window.removeEventListener('pointermove', onPointer));
  });
}
