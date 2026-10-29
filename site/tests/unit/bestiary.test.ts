import { existsSync, statSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { BESTIARY, GENTLE, HOSTILE, altOf, hourLabel, plateNumber } from '../../src/data/bestiary';

describe('bestiary', () => {
  it('has 7 gentle then 5 hostile plants with unique ids', () => {
    expect(BESTIARY).toHaveLength(12);
    expect(new Set(BESTIARY.map((s) => s.id)).size).toBe(12);
    expect(GENTLE).toHaveLength(7);
    expect(HOSTILE).toHaveLength(5);
    expect(BESTIARY.slice(0, 7).every((s) => !s.hostile)).toBe(true);
  });

  it('carries no provisional prefix and one WebP of at most 15 KB per plant', () => {
    for (const s of BESTIARY) {
      expect(s.fragment, s.id).not.toMatch(/provisoire/i);
      const file = resolve('public', s.image.slice(1));
      expect(existsSync(file), s.image).toBe(true);
      expect(statSync(file).size, s.image).toBeLessThanOrEqual(15 * 1024);
    }
  });

  it('formats number, alt and hour', () => {
    expect(plateNumber(BESTIARY[11]!)).toBe('012');
    expect(altOf(BESTIARY[6]!)).toBe("Lumiole, plante de l'espoir");
    expect(altOf(BESTIARY[10]!)).toBe('Ortie-Regret, plante du regret');
    expect(hourLabel(BESTIARY[0]!)).toBe('dès la tombée du sommeil');
    expect(hourLabel(BESTIARY[3]!)).toBe('dès 1 h');
  });
});
