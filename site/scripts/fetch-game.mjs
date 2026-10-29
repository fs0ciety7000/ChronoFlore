// Downloads the Web build of the game (asset chronoflore-web.zip of the rolling
// release `game-web-latest`, built by .github/workflows/game-web.yml) and
// unzips it into public/jouer/. The repo is private, so the GitHub API needs
// GAME_RELEASE_TOKEN (fine-grained PAT, Contents: read on this repo).
// Never fails the site build: without a token, or if anything goes wrong, it
// warns and writes a "coming soon" page at /jouer/ instead.
// Usage: npm run fetch:game
// Env: GAME_RELEASE_TOKEN, GAME_RELEASE_REPO (owner/name), GAME_RELEASE_API
// (API base URL, for local tests).
import { mkdir, rm, writeFile } from 'node:fs/promises';
import { dirname, join, normalize, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { inflateRawSync } from 'node:zlib';

export const RELEASE_TAG = 'game-web-latest';
export const ASSET_NAME = 'chronoflore-web.zip';
const DEFAULT_REPO = 'fs0ciety7000/ChronoFlore';
const DEFAULT_API = 'https://api.github.com';
const TIMEOUT_MS = 120_000;

/**
 * Minimal ZIP reader (stored and deflated entries, no ZIP64, no encryption).
 * @param {Uint8Array} bytes
 * @returns {{ name: string, data: Uint8Array }[]} Files only (no directories).
 */
export function unzip(bytes) {
  const buf = Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 22 - 0xffff); i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new Error('not a zip archive (no end of central directory)');
  const count = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);
  const files = [];
  for (let n = 0; n < count; n++) {
    if (buf.readUInt32LE(p) !== 0x02014b50) throw new Error('corrupt zip central directory');
    const flags = buf.readUInt16LE(p + 8);
    const method = buf.readUInt16LE(p + 10);
    const compSize = buf.readUInt32LE(p + 20);
    const size = buf.readUInt32LE(p + 24);
    const nameLen = buf.readUInt16LE(p + 28);
    const extraLen = buf.readUInt16LE(p + 30);
    const commentLen = buf.readUInt16LE(p + 32);
    const local = buf.readUInt32LE(p + 42);
    const name = buf.toString('utf8', p + 46, p + 46 + nameLen);
    p += 46 + nameLen + extraLen + commentLen;
    if (name.endsWith('/')) continue;
    if (flags & 1) throw new Error(`encrypted zip entry: ${name}`);
    if (buf.readUInt32LE(local) !== 0x04034b50) throw new Error(`corrupt zip entry: ${name}`);
    const start = local + 30 + buf.readUInt16LE(local + 26) + buf.readUInt16LE(local + 28);
    const raw = buf.subarray(start, start + compSize);
    let data;
    if (method === 0) data = raw;
    else if (method === 8) data = inflateRawSync(raw);
    else throw new Error(`unsupported zip method ${method}: ${name}`);
    if (data.length !== size) throw new Error(`bad size for zip entry: ${name}`);
    files.push({ name, data: new Uint8Array(data) });
  }
  return files;
}

/** Path of a zip entry inside dir, or an error for absolute / `..` paths (zip slip). */
function safeJoin(dir, name) {
  const rel = normalize(name.replaceAll('\\', '/'));
  if (rel.startsWith('/') || rel === '..' || rel.startsWith(`..${sep}`) || /^[a-zA-Z]:/.test(rel)) {
    throw new Error(`unsafe path in zip: ${name}`);
  }
  return join(dir, rel);
}

export const PLACEHOLDER_HTML = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Jouer · ChronoFlore</title>
<style>
  :root { color-scheme: light; }
  html, body { height: 100%; margin: 0; }
  body {
    display: grid; place-items: center; padding: 1rem; box-sizing: border-box;
    background: #fbf3e4; color: #3b2c4a;
    font-family: "Nunito", "Fredoka", system-ui, -apple-system, "Segoe UI", sans-serif;
    text-align: center;
  }
  .card {
    max-width: 26rem; padding: 2.25rem 1.75rem; border-radius: 2rem;
    background: #fffaf1; box-shadow: 0 0 0 3px #f2dfc4, 0 18px 40px -24px #b88a5a;
  }
  .bud { font-size: 3rem; line-height: 1; margin: 0 0 0.75rem; }
  h1 { margin: 0 0 0.75rem; font-size: 1.75rem; line-height: 1.15; }
  p { margin: 0 0 1.5rem; line-height: 1.5; }
  a {
    display: inline-block; padding: 0.75rem 1.5rem; border-radius: 999px;
    background: #3b2c4a; color: #fffaf1; font-weight: 700; text-decoration: none;
  }
  a:focus-visible { outline: 3px solid #f08aa8; outline-offset: 3px; }
</style>
</head>
<body>
<main class="card">
  <p class="bud" aria-hidden="true">🌱</p>
  <h1>Le jeu arrive bientôt</h1>
  <p>La rêveuse prépare encore son filet. Reviens un peu plus tard pour capturer ta première plante.</p>
  <a href="/">Retour au site</a>
</main>
</body>
</html>
`;

/** Writes the "coming soon" page as dir/index.html (and nothing else). */
export async function writePlaceholder(dir) {
  await rm(dir, { recursive: true, force: true });
  await mkdir(dir, { recursive: true });
  await writeFile(join(dir, 'index.html'), PLACEHOLDER_HTML);
}

/**
 * Downloads the latest build and unzips it into dir.
 * @param {{ dir: string, token?: string, repo?: string, api?: string,
 *   fetchImpl?: typeof fetch }} opts
 * @returns {Promise<string[]>} Names of the files written.
 */
export async function downloadGame({ dir, token, repo = DEFAULT_REPO, api = DEFAULT_API, fetchImpl = fetch }) {
  if (!token) throw new Error('GAME_RELEASE_TOKEN is not set');
  const auth = { Authorization: `Bearer ${token}`, 'X-GitHub-Api-Version': '2022-11-28' };
  const relRes = await fetchImpl(`${api}/repos/${repo}/releases/tags/${RELEASE_TAG}`, {
    headers: { ...auth, Accept: 'application/vnd.github+json' },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!relRes.ok) throw new Error(`release ${RELEASE_TAG}: HTTP ${relRes.status}`);
  const release = await relRes.json();
  const asset = (release.assets ?? []).find((a) => a.name === ASSET_NAME);
  if (!asset) throw new Error(`release ${RELEASE_TAG} has no ${ASSET_NAME}`);
  // The asset API URL redirects to storage; fetch drops Authorization on the
  // cross-origin redirect.
  const zipRes = await fetchImpl(asset.url, {
    headers: { ...auth, Accept: 'application/octet-stream' },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!zipRes.ok) throw new Error(`${ASSET_NAME}: HTTP ${zipRes.status}`);
  const files = unzip(new Uint8Array(await zipRes.arrayBuffer()));
  if (!files.some((f) => f.name === 'index.html')) throw new Error(`${ASSET_NAME} has no index.html at its root`);
  const targets = files.map((f) => ({ path: safeJoin(dir, f.name), data: f.data }));

  await rm(dir, { recursive: true, force: true });
  for (const t of targets) {
    await mkdir(dirname(t.path), { recursive: true });
    await writeFile(t.path, t.data);
  }
  return files.map((f) => f.name);
}

/**
 * Downloads the game, or writes the placeholder on any failure.
 * @returns {Promise<{ game: boolean, files?: string[], reason?: string }>}
 */
export async function fetchGame(opts, warn = console.warn) {
  try {
    return { game: true, files: await downloadGame(opts) };
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    warn(`fetch:game: ${reason}; writing the "coming soon" page instead.`);
    await writePlaceholder(opts.dir);
    return { game: false, reason };
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const dir = fileURLToPath(new URL('../public/jouer/', import.meta.url));
  const result = await fetchGame({
    dir,
    token: process.env.GAME_RELEASE_TOKEN,
    repo: process.env.GAME_RELEASE_REPO || undefined,
    api: process.env.GAME_RELEASE_API || undefined,
  });
  console.log(
    result.game
      ? `fetch:game: ${result.files.length} files -> public/jouer/`
      : 'fetch:game: placeholder -> public/jouer/index.html',
  );
}
