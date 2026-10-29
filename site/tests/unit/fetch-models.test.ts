import { mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { fetchModels } from '../../scripts/fetch-models.mjs';

const dirs: string[] = [];
const tmp = () => {
  const d = mkdtempSync(join(tmpdir(), 'models-'));
  dirs.push(d);
  return d;
};
afterEach(() => dirs.splice(0).forEach((d) => rmSync(d, { recursive: true, force: true })));

const body = (id: string) => new TextEncoder().encode(`glTF:${id}`);
const sha8 = (b: Uint8Array) => createHash('sha256').update(b).digest('hex').slice(0, 8);

function fakeFetch(failing: string[] = []) {
  const calls: string[] = [];
  const impl = async (url: string) => {
    calls.push(url);
    const id = url.match(/cdn\/(.+)\.glb$/)![1];
    if (failing.includes(id)) return new Response('nope', { status: 404 });
    return new Response(body(id), { status: 200 });
  };
  return { impl, calls };
}

describe('fetchModels', () => {
  it('writes versioned GLBs and a manifest when every download succeeds', async () => {
    const dir = tmp();
    const { impl, calls } = fakeFetch();
    await fetchModels(['a-1', 'b-2'], dir, impl);
    expect(calls).toEqual(['https://polyfork.dev/cdn/a-1.glb', 'https://polyfork.dev/cdn/b-2.glb']);
    const manifest = JSON.parse(readFileSync(join(dir, 'manifest.json'), 'utf8'));
    expect(manifest).toEqual({ 'a-1': `a-1.${sha8(body('a-1'))}.glb`, 'b-2': `b-2.${sha8(body('b-2'))}.glb` });
    expect(readFileSync(join(dir, manifest['a-1']))).toEqual(Buffer.from(body('a-1')));
  });

  it('rejects with the failing ids on a 404 and writes no manifest', async () => {
    const dir = tmp();
    const { impl } = fakeFetch(['b-2']);
    await expect(fetchModels(['a-1', 'b-2'], dir, impl)).rejects.toThrow(/b-2/);
    expect(readdirSync(dir)).not.toContain('manifest.json');
  });

  it('removes stale versions of the models', async () => {
    const dir = tmp();
    writeFileSync(join(dir, 'a-1.deadbeef.glb'), 'old');
    await fetchModels(['a-1'], dir, fakeFetch().impl);
    expect(readdirSync(dir).sort()).toEqual([`a-1.${sha8(body('a-1'))}.glb`, 'manifest.json']);
  });
});
