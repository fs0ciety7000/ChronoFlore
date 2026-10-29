import { describe, expect, it } from 'vitest';
import { detectOs, formatSize, parseManifest } from '../../src/scripts/downloads';

describe('parseManifest', () => {
  it('keeps valid entries', () => {
    const m = parseManifest({
      version: '0.1.42',
      date: '2026-10-29T12:00:00Z',
      files: { macos: { name: 'ChronoFlore-macos.dmg', size: 65_000_000 }, deb: { name: 'ChronoFlore-linux.deb', size: 9 } },
    });
    expect(m).toEqual({
      version: '0.1.42',
      date: '2026-10-29T12:00:00Z',
      files: { macos: { name: 'ChronoFlore-macos.dmg', size: 65_000_000 }, deb: { name: 'ChronoFlore-linux.deb', size: 9 } },
    });
  });

  it('drops malformed or unsafe entries and never throws', () => {
    expect(parseManifest(null)).toEqual({ files: {} });
    expect(parseManifest('x')).toEqual({ files: {} });
    expect(
      parseManifest({
        version: '<script>',
        date: 'never',
        files: {
          macos: { name: '../etc/passwd', size: 1 },
          windows: { name: 'ok.exe', size: 0 },
          deb: { name: 'ok.deb', size: '12' },
          tarball: { name: 'ok.tar.gz' },
          other: { name: 'x.zip', size: 1 },
        },
      }),
    ).toEqual({ files: {} });
  });
});

describe('formatSize', () => {
  it('formats in French decimal units', () => {
    expect(formatSize(111_208_848)).toBe('111 Mo');
    expect(formatSize(8_400_000)).toBe('8,4 Mo');
    expect(formatSize(640_000)).toBe('640 ko');
    expect(formatSize(12)).toBe('1 ko');
  });
});

describe('detectOs', () => {
  it.each([
    ['Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)', '', 'macos'],
    ['Mozilla/5.0 (Windows NT 10.0; Win64; x64)', 'Win32', 'windows'],
    ['Mozilla/5.0 (X11; Linux x86_64)', 'Linux x86_64', 'linux'],
    ['Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:130.0)', '', 'linux'],
    ['Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)', 'iPhone', null],
    ['Mozilla/5.0 (Linux; Android 15; Pixel 9) Mobile', 'Linux armv8l', null],
    ['curl/8.5', '', null],
  ])('%s -> %s', (ua, platform, os) => {
    expect(detectOs(ua, platform)).toBe(os);
  });
});
