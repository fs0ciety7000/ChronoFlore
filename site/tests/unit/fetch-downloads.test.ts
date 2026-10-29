import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { DOWNLOADS, fetchDownloads } from '../../scripts/fetch-downloads.mjs';

const dirs: string[] = [];
const tmp = () => {
  const d = mkdtempSync(join(tmpdir(), 'downloads-'));
  dirs.push(d);
  return join(d, 'telecharger');
};
afterEach(() => dirs.splice(0).forEach((d) => rmSync(d, { recursive: true, force: true })));

const CONTENT: Record<string, string> = {
  'ChronoFlore-macos.dmg': 'dmg-bytes',
  'ChronoFlore-windows.exe': 'MZ-windows',
  'ChronoFlore-linux.deb': '!<arch>\ndebian',
  'ChronoFlore-linux.tar.gz': 'gzip',
};
const INFO = { version: '0.1.42', commit: 'abc123', date: '2026-10-29T12:00:00Z' };

function fakeGitHub(
  opts: { releaseStatus?: number; skip?: string[]; badSize?: string; failing?: string; info?: unknown } = {},
) {
  const calls: { url: string; headers: Record<string, string> }[] = [];
  const names = [...Object.keys(CONTENT), 'chronoflore-desktop.json'].filter((n) => !opts.skip?.includes(n));
  const impl = async (url: string, init?: { headers?: Record<string, string> }) => {
    calls.push({ url, headers: init?.headers ?? {} });
    if (url.endsWith('/releases/tags/game-desktop-latest')) {
      if (opts.releaseStatus) return new Response('{}', { status: opts.releaseStatus });
      return Response.json({
        assets: names.map((name, i) => ({
          name,
          url: `https://api.test/assets/${i}`,
          size: name === opts.badSize ? 1 : Buffer.byteLength(CONTENT[name] ?? JSON.stringify(opts.info ?? INFO)),
        })),
      });
    }
    const m = /assets\/(\d+)$/.exec(url);
    const name = m ? names[Number(m[1])] : undefined;
    if (!name || name === opts.failing) return new Response('nope', { status: 500 });
    return new Response(CONTENT[name] ?? JSON.stringify(opts.info ?? INFO), { status: 200 });
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
const manifestOf = (dir: string) => JSON.parse(readFileSync(join(dir, 'manifest.json'), 'utf8'));

describe('fetchDownloads', () => {
  it('downloads every build and writes the manifest', async () => {
    const dir = tmp();
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, 'stale.exe'), 'old');
    const { impl, calls } = fakeGitHub();
    const warnings: string[] = [];
    const manifest = await fetchDownloads(opts(dir, impl), (m: string) => warnings.push(m));
    expect(warnings).toEqual([]);
    expect(calls[0].url).toBe('https://api.test/repos/owner/repo/releases/tags/game-desktop-latest');
    expect(calls.every((c) => c.headers.Authorization === 'Bearer tok')).toBe(true);
    expect(calls.slice(1).every((c) => c.headers.Accept === 'application/octet-stream')).toBe(true);
    expect(readdirSync(dir).sort()).toEqual([...Object.keys(CONTENT), 'manifest.json'].sort());
    expect(readFileSync(join(dir, 'ChronoFlore-windows.exe'), 'utf8')).toBe('MZ-windows');
    expect(manifest).toEqual({
      ...INFO,
      files: Object.fromEntries(
        Object.entries(DOWNLOADS).map(([key, name]) => [key, { name, size: Buffer.byteLength(CONTENT[name]) }]),
      ),
    });
    expect(manifestOf(dir)).toEqual(manifest);
  });

  it('leaves out a file that is missing, fails or has the wrong size, and keeps the others', async () => {
    const dir = tmp();
    const { impl } = fakeGitHub({
      skip: ['ChronoFlore-macos.dmg'],
      failing: 'ChronoFlore-linux.deb',
      badSize: 'ChronoFlore-linux.tar.gz',
    });
    const warnings: string[] = [];
    const manifest = await fetchDownloads(opts(dir, impl), (m: string) => warnings.push(m));
    expect(Object.keys(manifest.files)).toEqual(['windows']);
    expect(warnings).toHaveLength(3);
    expect(readdirSync(dir).sort()).toEqual(['ChronoFlore-windows.exe', 'manifest.json']);
  });

  it('ignores a malformed build info file', async () => {
    const { impl } = fakeGitHub({ info: { version: 42, commit: 'x'.repeat(500) } });
    const manifest = await fetchDownloads(opts(tmp(), impl), () => {});
    expect(manifest.version).toBeUndefined();
    expect(manifest.commit).toBeUndefined();
    expect(Object.keys(manifest.files)).toHaveLength(4);
  });

  it.each([
    ['the token is missing', fakeGitHub().impl, null, /GAME_RELEASE_TOKEN/],
    ['the release is missing', fakeGitHub({ releaseStatus: 404 }).impl, 'tok', /HTTP 404/],
    [
      'the network fails',
      async () => {
        throw new TypeError('fetch failed');
      },
      'tok',
      /fetch failed/,
    ],
  ])('writes an empty manifest when %s', async (_label, impl, token, reason) => {
    const dir = tmp();
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, 'ChronoFlore-windows.exe'), 'stale');
    const warnings: string[] = [];
    const manifest = await fetchDownloads(opts(dir, impl, token), (m: string) => warnings.push(m));
    expect(manifest).toEqual({ files: {} });
    expect(warnings).toHaveLength(1);
    expect(warnings[0]).toMatch(reason);
    expect(readdirSync(dir)).toEqual(['manifest.json']);
    expect(manifestOf(dir)).toEqual({ files: {} });
  });

  it('never prints the token', async () => {
    const warnings: string[] = [];
    await fetchDownloads(opts(tmp(), fakeGitHub({ releaseStatus: 401 }).impl, 'secret-token'), (m: string) =>
      warnings.push(m),
    );
    expect(warnings.join('\n')).not.toContain('secret-token');
  });
});
