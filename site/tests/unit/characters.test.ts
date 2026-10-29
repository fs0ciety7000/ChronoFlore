import { createHash } from 'node:crypto';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { CHARACTERS, CHARACTER_CLIPS, CUSTOM_MODELS_URL } from '../../src/scripts/characters';

const publicDir = new URL('../../public/', import.meta.url);
const fileOf = (name: string) => new URL(`.${CUSTOM_MODELS_URL}${name}`, publicDir);

/** JSON chunk of a binary glTF. */
function gltfJson(bytes: Buffer) {
  expect(bytes.toString('ascii', 0, 4)).toBe('glTF');
  const len = bytes.readUInt32LE(12);
  return JSON.parse(bytes.toString('utf8', 20, 20 + len));
}

describe('CHARACTERS (home-made heroine and companion)', () => {
  it('lists the heroine and the companion', () => {
    expect(Object.keys(CHARACTERS).sort()).toEqual(['companion', 'heroine']);
  });

  for (const [key, c] of Object.entries(CHARACTERS)) {
    it(`${key}: committed under a content-hashed name`, () => {
      const url = fileOf(c.file);
      expect(existsSync(url), c.file).toBe(true);
      const bytes = readFileSync(url);
      const sha8 = createHash('sha256').update(bytes).digest('hex').slice(0, 8);
      expect(c.file).toMatch(/^[a-z0-9-]+\.[0-9a-f]{8}\.glb$/);
      expect(c.file.split('.')[1], 'hash in the file name').toBe(sha8);
    });

    it(`${key}: carries the Idle, Walk, Swing and Hurt clips`, () => {
      const json = gltfJson(readFileSync(fileOf(c.file)));
      const names = (json.animations ?? []).map((a: { name: string }) => a.name);
      for (const clip of CHARACTER_CLIPS) expect(names, key).toContain(clip);
      expect(json.skins?.length).toBeGreaterThanOrEqual(1);
    });
  }

  it('keeps both models under 1 MB together', () => {
    const total = Object.values(CHARACTERS).reduce((n, c) => n + statSync(fileOf(c.file)).size, 0);
    expect(total).toBeLessThan(1024 * 1024);
  });

  it('labels the portraits exactly as the spec says', () => {
    expect(CHARACTERS.heroine.label).toBe("L'héroïne en 3D : peau foncée, longues tresses, lunettes roses, haut à rayures");
    expect(CHARACTERS.companion.label).toBe('Le compagnon en 3D : casquette de tweed grise, veste kaki, barbe courte');
  });
});
