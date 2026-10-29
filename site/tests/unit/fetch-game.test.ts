import { mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { crc32, deflateRawSync } from 'node:zlib';
import { afterEach, describe, expect, it } from 'vitest';
import { ASSET_NAME, PLACEHOLDER_HTML, fetchGame, unzip } from '../../scripts/fetch-game.mjs';

const dirs: string[] = [];
const tmp = () => {
  const d = mkdtempSync(join(tmpdir(), 'game-'));
  dirs.push(d);
  return join(d, 'jouer');
};
afterEach(() => dirs.splice(0).forEach((d) => rmSync(d, { recursive: true, force: true })));

/** Builds a zip archive: deflated entries, plus stored ones for names ending in `.stored`. */
function makeZip(entries: Record<string, string | Uint8Array>): Uint8Array {
  const locals: Buffer[] = [];
  const centrals: Buffer[] = [];
  let offset = 0;
  for (const [name, content] of Object.entries(entries)) {
    const data = Buffer.from(typeof content === 'string' ? new TextEncoder().encode(content) : content);
    const stored = name.endsWith('/') || name.endsWith('.stored');
    const body = stored ? data : deflateRawSync(data);
    const nameBuf = Buffer.from(name, 'utf8');
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(stored ? 0 : 8, 8);
    local.writeUInt32LE(crc32(data), 14);
    local.writeUInt32LE(body.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(nameBuf.length, 26);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(stored ? 0 : 8, 10);
    central.writeUInt32LE(crc32(data), 16);
    central.writeUInt32LE(body.length, 20);
    central.writeUInt32LE(data.length, 24);
    central.writeUInt16LE(nameBuf.length, 28);
    central.writeUInt32LE(offset, 42);
    locals.push(local, nameBuf, body);
    centrals.push(central, nameBuf);
    offset += 30 + nameBuf.length + body.length;
  }
  const cd = Buffer.concat(centrals);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(Object.keys(entries).length, 8);
  eocd.writeUInt16LE(Object.keys(entries).length, 10);
  eocd.writeUInt32LE(cd.length, 12);
  eocd.writeUInt32LE(offset, 16);
  return new Uint8Array(Buffer.concat([...locals, cd, eocd]));
}

const GAME = {
  'index.html': '<!doctype html><title>ChronoFlore</title>',
  'index.wasm': new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0]),
  'index.pck.stored': 'GDPC',
  'audio/': '',
  'audio/index.audio.worklet.js': 'registerProcessor()',
};

function fakeGitHub(zip: Uint8Array, opts: { releaseStatus?: number; assetName?: string } = {}) {
  const calls: { url: string; headers: Record<string, string> }[] = [];
  const impl = async (url: string, init?: { headers?: Record<string, string>; signal?: AbortSignal }) => {
    calls.push({ url, headers: init?.headers ?? {} });
    if (url.endsWith('/releases/tags/game-web-latest')) {
      if (opts.releaseStatus) return new Response('{}', { status: opts.releaseStatus });
      return Response.json({
        assets: [
          { name: 'other.zip', url: 'https://api.test/assets/1' },
          { name: opts.assetName ?? ASSET_NAME, url: 'https://api.test/assets/2' },
        ],
      });
    }
    if (url === 'https://api.test/assets/2') return new Response(Buffer.from(zip), { status: 200 });
    return new Response('nope', { status: 404 });
  };
  return { impl, calls };
}

const opts = (dir: string, fetchImpl: unknown, token: string | null = 'tok') => ({
  dir,
  token,
  repo: 'owner/repo',
  api: 'https://api.test',
  fetchImpl: fetchImpl as typeof fetch,
});

describe('unzip', () => {
  it('reads deflated and stored entries and skips directories', () => {
    const files = unzip(makeZip(GAME));
    expect(files.map((f) => f.name)).toEqual([
      'index.html',
      'index.wasm',
      'index.pck.stored',
      'audio/index.audio.worklet.js',
    ]);
    expect(new TextDecoder().decode(files[0].data)).toBe(GAME['index.html']);
    expect([...files[1].data]).toEqual([...GAME['index.wasm']]);
  });

  it('rejects data that is not a zip', () => {
    expect(() => unzip(new TextEncoder().encode('<html>not found</html>'))).toThrow(/not a zip/);
  });
});

describe('fetchGame', () => {
  it('unzips the release asset into the directory', async () => {
    const dir = tmp();
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, 'stale.js'), 'old');
    const { impl, calls } = fakeGitHub(makeZip(GAME));
    const result = await fetchGame(opts(dir, impl), () => {});
    expect(result.game).toBe(true);
    expect(calls.map((c) => c.url)).toEqual([
      'https://api.test/repos/owner/repo/releases/tags/game-web-latest',
      'https://api.test/assets/2',
    ]);
    expect(calls[0].headers.Authorization).toBe('Bearer tok');
    expect(calls[1].headers.Accept).toBe('application/octet-stream');
    expect(readdirSync(dir).sort()).toEqual(['audio', 'index.html', 'index.pck.stored', 'index.wasm']);
    expect(readFileSync(join(dir, 'index.html'), 'utf8')).toBe(GAME['index.html']);
    expect(readFileSync(join(dir, 'audio/index.audio.worklet.js'), 'utf8')).toBe('registerProcessor()');
  });

  it('writes the placeholder without calling the API when the token is missing', async () => {
    const dir = tmp();
    const { impl, calls } = fakeGitHub(makeZip(GAME));
    const warnings: string[] = [];
    const result = await fetchGame(opts(dir, impl, null), (m: string) => warnings.push(m));
    expect(result).toEqual({ game: false, reason: 'GAME_RELEASE_TOKEN is not set' });
    expect(calls).toEqual([]);
    expect(warnings[0]).toMatch(/GAME_RELEASE_TOKEN/);
    expect(readdirSync(dir)).toEqual(['index.html']);
    const html = readFileSync(join(dir, 'index.html'), 'utf8');
    expect(html).toBe(PLACEHOLDER_HTML);
    expect(html).toContain('Le jeu arrive bientôt');
    expect(html).toContain('href="/"');
  });

  it.each([
    ['the release is missing', fakeGitHub(makeZip(GAME), { releaseStatus: 404 }).impl, /HTTP 404/],
    ['the asset is missing', fakeGitHub(makeZip(GAME), { assetName: 'x.zip' }).impl, /no chronoflore-web\.zip/],
    ['the asset has no index.html', fakeGitHub(makeZip({ 'game.html': 'x' })).impl, /no index\.html/],
    ['the asset escapes the directory', fakeGitHub(makeZip({ 'index.html': 'x', '../evil.js': 'x' })).impl, /unsafe/],
    [
      'the network fails',
      async () => {
        throw new TypeError('fetch failed');
      },
      /fetch failed/,
    ],
  ])('falls back to the placeholder when %s', async (_label, impl, reason) => {
    const dir = tmp();
    const warnings: string[] = [];
    const result = await fetchGame(opts(dir, impl), (m: string) => warnings.push(m));
    expect(result.game).toBe(false);
    expect(result.reason).toMatch(reason);
    expect(warnings).toHaveLength(1);
    expect(readdirSync(dir)).toEqual(['index.html']);
    expect(readFileSync(join(dir, 'index.html'), 'utf8')).toBe(PLACEHOLDER_HTML);
  });

  it('never prints the token', async () => {
    const warnings: string[] = [];
    const { impl } = fakeGitHub(makeZip(GAME), { releaseStatus: 401 });
    await fetchGame(opts(tmp(), impl, 'secret-token'), (m: string) => warnings.push(m));
    expect(warnings.join('\n')).not.toContain('secret-token');
  });
});
