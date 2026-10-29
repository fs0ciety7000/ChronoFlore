import { describe, expect, it } from 'vitest';
import { shouldUse3D, type Env } from '../../src/scripts/env';

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
