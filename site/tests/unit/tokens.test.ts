import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { PALETTES } from '../../src/scripts/timeline';

const css = readFileSync(new URL('../../src/styles/tokens.css', import.meta.url), 'utf8');

function token(name: string): string | undefined {
  return css.match(new RegExp(`^\\s*--${name}:\\s*([^;]+);`, 'm'))?.[1].trim().toLowerCase();
}

describe('tokens.css', () => {
  it('starts the scroll-driven palette at PALETTES.day', () => {
    for (const key of ['bg', 'ink', 'accent', 'surface'] as const) {
      expect(token(key), `--${key}`).toBe(PALETTES.day[key]);
    }
    expect(token('progress')).toBe('0');
  });
});
