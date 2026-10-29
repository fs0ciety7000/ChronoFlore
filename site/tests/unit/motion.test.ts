import { describe, expect, it } from 'vitest';
import { handRotation } from '../../src/scripts/clock-hand';
import { REVEAL_STAGGER_MS, revealDelay } from '../../src/scripts/reveal';

describe('handRotation', () => {
  it('maps progress to one full turn', () => {
    expect(handRotation(0)).toBe('rotate(0deg)');
    expect(handRotation(0.5)).toBe('rotate(180deg)');
    expect(handRotation(1)).toBe('rotate(360deg)');
  });
  it('clamps out-of-range progress', () => {
    expect(handRotation(-0.2)).toBe('rotate(0deg)');
    expect(handRotation(1.4)).toBe('rotate(360deg)');
  });
});

describe('revealDelay', () => {
  it('cascades by 60ms and caps the wait', () => {
    expect(REVEAL_STAGGER_MS).toBe(60);
    expect([0, 1, 2, 3].map(revealDelay)).toEqual([0, 60, 120, 180]);
    expect(revealDelay(12)).toBe(300);
  });
});
