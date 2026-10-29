import { describe, expect, it } from 'vitest';
import { probeWebGL, shouldUse3D, type Env } from '../../src/scripts/env';

const capable: Env = {
  reducedMotion: false,
  finePointer: true,
  webgl: true,
  saveData: false,
  deviceMemory: 8,
};

describe('shouldUse3D', () => {
  it('is true for a capable device', () => {
    expect(shouldUse3D(capable)).toBe(true);
  });

  it('is true when deviceMemory is unknown', () => {
    expect(shouldUse3D({ ...capable, deviceMemory: undefined })).toBe(true);
  });

  it.each([
    ['reducedMotion', { reducedMotion: true }],
    ['no webgl', { webgl: false }],
    ['saveData', { saveData: true }],
    ['low deviceMemory', { deviceMemory: 2 }],
  ])('is false for %s', (_name, patch) => {
    expect(shouldUse3D({ ...capable, ...patch })).toBe(false);
  });
});

describe('shouldUse3D probes WebGL lazily', () => {
  it('does not read webgl when another rule already says no', () => {
    let probed = 0;
    const env = {
      ...capable,
      reducedMotion: true,
      get webgl() {
        probed++;
        return true;
      },
    };
    expect(shouldUse3D(env)).toBe(false);
    expect(probed).toBe(0);
  });
});

describe('probeWebGL', () => {
  const fakeDoc = (ctx: unknown) => {
    const calls: string[] = [];
    const doc = {
      createElement: () => ({
        getContext: (kind: string) => {
          calls.push(`getContext:${kind}`);
          return ctx;
        },
      }),
    };
    return { doc: doc as unknown as Document, calls };
  };

  it('releases the probe context', () => {
    let lost = 0;
    const ctx = { getExtension: (name: string) => (name === 'WEBGL_lose_context' ? { loseContext: () => lost++ } : null) };
    const { doc } = fakeDoc(ctx);
    expect(probeWebGL(doc)).toBe(true);
    expect(lost).toBe(1);
  });

  it('is false without a context', () => {
    expect(probeWebGL(fakeDoc(null).doc)).toBe(false);
  });
});
