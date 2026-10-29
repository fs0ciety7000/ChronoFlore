// Downloads the Polyfork models of the diorama into public/models/polyfork/.
// Files are named {id}.{sha8}.glb (nginx serves /models/ as immutable), and
// manifest.json maps each id to its file. The manifest is only written when
// every model downloaded, so a failed fetch fails the build.
// Usage: npm run fetch:models
import { createHash } from 'node:crypto';
import { mkdir, readdir, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const CDN = 'https://polyfork.dev/cdn';
const TIMEOUT_MS = 30_000;
const GLB_MAGIC = 'glTF';

/**
 * @param {string[]} ids Polyfork model ids.
 * @param {string} dir Output directory.
 * @param {(url: string, init?: { signal?: AbortSignal }) => Promise<Response>} [fetchImpl]
 */
export async function fetchModels(ids, dir, fetchImpl = fetch) {
  await mkdir(dir, { recursive: true });
  const failed = [];
  const files = {};
  for (const id of ids) {
    try {
      const res = await fetchImpl(`${CDN}/${id}.glb`, { signal: AbortSignal.timeout(TIMEOUT_MS) });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const bytes = new Uint8Array(await res.arrayBuffer());
      if (new TextDecoder().decode(bytes.subarray(0, 4)) !== GLB_MAGIC) throw new Error(`not a GLB (no ${GLB_MAGIC} header)`);
      const sha8 = createHash('sha256').update(bytes).digest('hex').slice(0, 8);
      files[id] = { name: `${id}.${sha8}.glb`, bytes };
    } catch (err) {
      failed.push(`${id} (${err instanceof Error ? err.message : err})`);
    }
  }
  if (failed.length) throw new Error(`Polyfork download failed for: ${failed.join(', ')}`);

  const manifest = {};
  for (const id of ids) {
    await writeFile(join(dir, files[id].name), files[id].bytes);
    manifest[id] = files[id].name;
  }
  // Drop older versions so the deployed folder only holds what the scene loads.
  const keep = new Set([...Object.values(manifest), 'manifest.json']);
  for (const name of await readdir(dir)) {
    if (name.endsWith('.glb') && !keep.has(name)) await rm(join(dir, name));
  }
  await writeFile(join(dir, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  return manifest;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  // Node >= 22.18 strips the types of island.ts (pure data, no relative imports).
  const { modelIds } = await import('../src/scripts/diorama/island.ts');
  const dir = fileURLToPath(new URL('../public/models/polyfork/', import.meta.url));
  const manifest = await fetchModels(modelIds(), dir);
  console.log(`fetch:models: ${Object.keys(manifest).length} models -> public/models/polyfork/`);
}
