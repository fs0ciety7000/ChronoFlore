import { describe, expect, it } from 'vitest';
import { mixHex } from '../../src/scripts/color';

describe('mixHex', () => {
  it('mixes halfway', () => {
    expect(mixHex('#000000', '#ffffff', 0.5)).toBe('#808080');
  });
  it('clamps t to [0,1]', () => {
    expect(mixHex('#f6f1e7', '#22203a', 0)).toBe('#f6f1e7');
    expect(mixHex('#f6f1e7', '#22203a', 2)).toBe('#22203a');
    expect(mixHex('#f6f1e7', '#22203a', -1)).toBe('#f6f1e7');
  });
});
