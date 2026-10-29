import { describe, expect, it, vi } from 'vitest';
import { SHARE_TEXT, SHARE_URL, sharePage, shareLinks } from '../../src/scripts/share';

describe('shareLinks', () => {
  it('encodes url and text for each network', () => {
    const l = shareLinks('https://a.test/?x=1&y=2', 'a & b é');
    expect(l.bluesky).toBe('https://bsky.app/intent/compose?text=' + encodeURIComponent('a & b é'));
    expect(l.x).toBe(
      'https://x.com/intent/post?text=' +
        encodeURIComponent('a & b é') +
        '&url=' +
        encodeURIComponent('https://a.test/?x=1&y=2'),
    );
    expect(l.facebook).toBe(
      'https://www.facebook.com/sharer/sharer.php?u=' + encodeURIComponent('https://a.test/?x=1&y=2'),
    );
    expect(l.bluesky).toContain('%26');
  });
  it('exposes the canonical constants', () => {
    expect(SHARE_URL).toBe('https://chronoflore.cardormedia.com/');
    expect(SHARE_TEXT).toBe('ChronoFlore — deux heures de sommeil, toute une flore à capturer.');
  });
});

describe('sharePage', () => {
  const U = SHARE_URL;
  const T = SHARE_TEXT;
  it('uses navigator.share when present', async () => {
    const share = vi.fn().mockResolvedValue(undefined);
    expect(await sharePage({ share } as never, U, T)).toBe('shared');
    expect(share).toHaveBeenCalledWith({ url: U, text: T, title: 'ChronoFlore' });
  });
  it('returns cancelled on AbortError', async () => {
    const share = vi.fn().mockRejectedValue(new DOMException('x', 'AbortError'));
    expect(await sharePage({ share } as never, U, T)).toBe('cancelled');
  });
  it('falls back to the clipboard', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    expect(await sharePage({ clipboard: { writeText } } as never, U, T)).toBe('copied');
    expect(writeText).toHaveBeenCalledWith(U);
  });
  it('falls back to the clipboard when share fails for another reason', async () => {
    const share = vi.fn().mockRejectedValue(new Error('nope'));
    const writeText = vi.fn().mockResolvedValue(undefined);
    expect(await sharePage({ share, clipboard: { writeText } } as never, U, T)).toBe('copied');
  });
  it('returns manual without clipboard or when it rejects', async () => {
    expect(await sharePage({} as never, U, T)).toBe('manual');
    const writeText = vi.fn().mockRejectedValue(new Error('denied'));
    expect(await sharePage({ clipboard: { writeText } } as never, U, T)).toBe('manual');
  });
});
