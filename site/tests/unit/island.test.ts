import { describe, expect, it } from 'vitest';
import { ALLOWED_IDS, ISLAND, ISLAND_RADIUS, modelIds } from '../../src/scripts/diorama/island';

const CLOUD = 'towering-cloud-2e00f1';
const count = (id: string) => ISLAND.filter((p) => p.id === id).length;

describe('ISLAND composition', () => {
  it('only uses the allowed Polyfork ids', () => {
    expect([...ALLOWED_IDS].sort()).toEqual(
      [
        'cherry-blossom-tree-3f7ab7',
        'pastel-flowering-plant-d16a03',
        'wildflower-plant-cf4279',
        'fern-plant-1559b8',
        'leafy-bush-d37bba',
        'grass-tuft-62e90c',
        'field-rock-5e37c6',
        CLOUD,
      ].sort(),
    );
    for (const p of ISLAND) expect(ALLOWED_IDS, p.id).toContain(p.id);
  });

  it('keeps every ground placement on the 12 m island disc', () => {
    expect(ISLAND_RADIUS).toBeLessThanOrEqual(12);
    for (const p of ISLAND.filter((q) => q.id !== CLOUD)) {
      expect(Math.hypot(p.x, p.z), `${p.id} at ${p.x},${p.z}`).toBeLessThanOrEqual(12);
    }
  });

  it('floats the clouds off the island', () => {
    for (const p of ISLAND.filter((q) => q.id === CLOUD)) {
      expect(Math.hypot(p.x, p.z)).toBeGreaterThan(12);
    }
  });

  it('has the required cherry trees, pastel flowers and clouds', () => {
    expect(count('cherry-blossom-tree-3f7ab7')).toBeGreaterThanOrEqual(1);
    expect(count('pastel-flowering-plant-d16a03')).toBeGreaterThanOrEqual(3);
    expect(count(CLOUD)).toBeGreaterThanOrEqual(3);
  });

  it('lists each model id once', () => {
    const ids = modelIds();
    expect(new Set(ids).size).toBe(ids.length);
    expect(new Set(ids)).toEqual(new Set(ISLAND.map((p) => p.id)));
  });
});
