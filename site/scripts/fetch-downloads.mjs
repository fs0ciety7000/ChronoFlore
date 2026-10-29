// Downloads the desktop builds of the game (rolling release
// `game-desktop-latest`, built by .github/workflows/game-desktop.yml) into
// public/telecharger/ and writes public/telecharger/manifest.json, which
// src/components/Downloads.astro reads at build time. The repo is private, so
// the GitHub API needs GAME_RELEASE_TOKEN (same PAT as fetch:game).
// Never fails the site build: without a token, or for any file that cannot be
// fetched, it warns and leaves that file out of the manifest; the site then
// shows "bientôt disponible" instead of a link.
// Usage: npm run fetch:downloads
// Env: GAME_RELEASE_TOKEN, GAME_RELEASE_REPO (owner/name), GAME_RELEASE_API
// (API base URL, for local tests).
import { createWriteStream } from 'node:fs';
import { mkdir, rename, rm, stat, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const RELEASE_TAG = 'game-desktop-latest';
export const INFO_ASSET = 'chronoflore-desktop.json';
/** Manifest key -> release asset name (served as /telecharger/<name>). */
export const DOWNLOADS = {
  macos: 'ChronoFlore-macos.dmg',
  windows: 'ChronoFlore-windows.exe',
  deb: 'ChronoFlore-linux.deb',
  tarball: 'ChronoFlore-linux.tar.gz',
};
export const MANIFEST_NAME = 'manifest.json';
const DEFAULT_REPO = 'fs0ciety7000/ChronoFlore';
const DEFAULT_API = 'https://api.github.com';
const TIMEOUT_MS = 600_000;

/** @typedef {{ version?: string, commit?: string, date?: string,
 *   files: Record<string, { name: string, size: number }> }} Manifest */

/** @returns {Manifest} */
export const emptyManifest = () => ({ files: {} });

/**
 * Downloads every desktop build it can into dir (replacing its contents).
 * @param {{ dir: string, token?: string, repo?: string, api?: string,
 *   fetchImpl?: typeof fetch }} opts
 * @param {(msg: string) => void} warn
 * @returns {Promise<Manifest>}
 */
export async function downloadAll({ dir, token, repo = DEFAULT_REPO, api = DEFAULT_API, fetchImpl = fetch }, warn) {
  if (!token) throw new Error('GAME_RELEASE_TOKEN is not set');
  const auth = { Authorization: `Bearer ${token}`, 'X-GitHub-Api-Version': '2022-11-28' };
  const relRes = await fetchImpl(`${api}/repos/${repo}/releases/tags/${RELEASE_TAG}`, {
    headers: { ...auth, Accept: 'application/vnd.github+json' },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!relRes.ok) throw new Error(`release ${RELEASE_TAG}: HTTP ${relRes.status}`);
  const assets = (await relRes.json()).assets ?? [];
  // The asset API URL redirects to storage; fetch drops Authorization on the
  // cross-origin redirect.
  const get = (asset) =>
    fetchImpl(asset.url, {
      headers: { ...auth, Accept: 'application/octet-stream' },
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });

  const manifest = emptyManifest();
  const info = assets.find((a) => a.name === INFO_ASSET);
  if (info) {
    try {
      const res = await get(info);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const { version, commit, date } = await res.json();
      for (const [k, v] of Object.entries({ version, commit, date })) {
        if (typeof v === 'string' && v.length <= 100) manifest[k] = v;
      }
    } catch (err) {
      warn(`fetch:downloads: ${INFO_ASSET}: ${err instanceof Error ? err.message : err}`);
    }
  }

  await rm(dir, { recursive: true, force: true });
  await mkdir(dir, { recursive: true });
  for (const [key, name] of Object.entries(DOWNLOADS)) {
    const path = join(dir, name);
    const part = `${path}.part`;
    try {
      const asset = assets.find((a) => a.name === name);
      if (!asset) throw new Error(`release ${RELEASE_TAG} has no ${name}`);
      const res = await get(asset);
      if (!res.ok || !res.body) throw new Error(`HTTP ${res.status}`);
      await pipeline(Readable.fromWeb(res.body), createWriteStream(part));
      const { size } = await stat(part);
      if (size === 0) throw new Error('empty file');
      if (typeof asset.size === 'number' && asset.size !== size) {
        throw new Error(`size ${size} differs from the release (${asset.size})`);
      }
      await rename(part, path);
      manifest.files[key] = { name, size };
    } catch (err) {
      await rm(part, { force: true });
      warn(`fetch:downloads: ${name}: ${err instanceof Error ? err.message : err}; left out.`);
    }
  }
  return manifest;
}

/**
 * Downloads the desktop builds and always writes dir/manifest.json (empty
 * `files` on any failure).
 * @returns {Promise<Manifest>}
 */
export async function fetchDownloads(opts, warn = console.warn) {
  let manifest;
  try {
    manifest = await downloadAll(opts, warn);
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    warn(`fetch:downloads: ${reason}; the site will show "bientôt disponible".`);
    await rm(opts.dir, { recursive: true, force: true });
    await mkdir(opts.dir, { recursive: true });
    manifest = emptyManifest();
  }
  await writeFile(join(opts.dir, MANIFEST_NAME), `${JSON.stringify(manifest, null, 2)}\n`);
  return manifest;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const dir = fileURLToPath(new URL('../public/telecharger/', import.meta.url));
  const manifest = await fetchDownloads({
    dir,
    token: process.env.GAME_RELEASE_TOKEN,
    repo: process.env.GAME_RELEASE_REPO || undefined,
    api: process.env.GAME_RELEASE_API || undefined,
  });
  const files = Object.values(manifest.files);
  const mb = files.reduce((n, f) => n + f.size, 0) / 1e6;
  console.log(`fetch:downloads: ${files.length} files (${mb.toFixed(1)} MB) -> public/telecharger/`);
}
