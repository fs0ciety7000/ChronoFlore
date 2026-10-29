// Desktop downloads: the manifest written by scripts/fetch-downloads.mjs and
// the helpers that render it (src/components/Downloads.astro).

export type Platform = 'macos' | 'windows' | 'deb' | 'tarball';
export type Os = 'macos' | 'windows' | 'linux';

export interface DownloadFile {
  name: string;
  size: number;
}

export interface DownloadManifest {
  version?: string;
  date?: string;
  files: Partial<Record<Platform, DownloadFile>>;
}

const PLATFORMS: Platform[] = ['macos', 'windows', 'deb', 'tarball'];
const SAFE_NAME = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

/** Validates untrusted JSON; anything malformed is dropped (never throws). */
export function parseManifest(raw: unknown): DownloadManifest {
  const out: DownloadManifest = { files: {} };
  if (!raw || typeof raw !== 'object') return out;
  const m = raw as Record<string, unknown>;
  if (typeof m.version === 'string' && /^[\w.+-]{1,40}$/.test(m.version)) out.version = m.version;
  if (typeof m.date === 'string' && !Number.isNaN(Date.parse(m.date))) out.date = m.date;
  const files = m.files && typeof m.files === 'object' ? (m.files as Record<string, unknown>) : {};
  for (const key of PLATFORMS) {
    const f = files[key] as Partial<DownloadFile> | undefined;
    if (f && typeof f.name === 'string' && SAFE_NAME.test(f.name) && Number.isSafeInteger(f.size) && f.size! > 0) {
      out.files[key] = { name: f.name, size: f.size! };
    }
  }
  return out;
}

/** "112 Mo", "8,4 Mo", "640 ko" (decimal units, French formatting). */
export function formatSize(bytes: number): string {
  const nbsp = ' ';
  if (bytes < 1e6) return `${Math.max(1, Math.round(bytes / 1e3))}${nbsp}ko`;
  const mb = bytes / 1e6;
  const value = mb < 10 ? mb.toLocaleString('fr-FR', { maximumFractionDigits: 1 }) : String(Math.round(mb));
  return `${value}${nbsp}Mo`;
}

/** The visitor's desktop OS, or null (phones, tablets, unknown). */
export function detectOs(userAgent: string, platform = ''): Os | null {
  const s = `${platform} ${userAgent}`;
  if (/android|iphone|ipad|ipod|mobile/i.test(s)) return null;
  if (/mac/i.test(s)) return 'macos';
  if (/win/i.test(s)) return 'windows';
  if (/linux|x11|ubuntu|debian|fedora/i.test(s)) return 'linux';
  return null;
}
