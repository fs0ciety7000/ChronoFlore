export const SHARE_URL = 'https://chronoflore.cardormedia.com/';
export const SHARE_TEXT = 'ChronoFlore — deux heures de sommeil, toute une flore à capturer.';

export type ShareOutcome = 'shared' | 'copied' | 'manual' | 'cancelled';

export function shareLinks(url: string, text: string): { bluesky: string; x: string; facebook: string } {
  const u = encodeURIComponent(url);
  const t = encodeURIComponent(text);
  return {
    bluesky: `https://bsky.app/intent/compose?text=${encodeURIComponent(`${text} ${url}`)}`,
    x: `https://x.com/intent/post?text=${t}&url=${u}`,
    facebook: `https://www.facebook.com/sharer/sharer.php?u=${u}`,
  };
}

async function copy(nav: Partial<Pick<Navigator, 'clipboard'>>, url: string): Promise<ShareOutcome> {
  try {
    await nav.clipboard!.writeText(url);
    return 'copied';
  } catch {
    return 'manual';
  }
}

/** Native share sheet when available, else clipboard, else ask the visitor to copy by hand. */
export async function sharePage(
  nav: Partial<Pick<Navigator, 'share' | 'clipboard'>>,
  url: string,
  text: string,
): Promise<ShareOutcome> {
  if (nav.share) {
    try {
      await nav.share({ url, text, title: 'ChronoFlore' });
      return 'shared';
    } catch (e) {
      if (e instanceof Error && e.name === 'AbortError') return 'cancelled';
    }
  }
  return copy(nav, url);
}

/** Wires the « Copier le lien » button and the hero's « Partager le rêve » action. */
export function initShare(): void {
  const copyBtn = document.querySelector<HTMLButtonElement>('[data-copy-link]');
  const primary = document.querySelector<HTMLAnchorElement>('[data-share-primary]');
  const manual = document.querySelector<HTMLElement>('[data-share-manual]');
  const idle = copyBtn?.textContent ?? 'Copier le lien';
  let timer: number | undefined;

  const showManual = () => {
    if (!manual) return;
    manual.hidden = false;
    const input = manual.querySelector('input')!;
    input.focus();
    input.select();
  };
  const status = document.querySelector<HTMLElement>('[data-share-status]');
  const confirm = () => {
    if (copyBtn) copyBtn.textContent = 'Lien copié';
    if (status) status.textContent = 'Lien copié';
    clearTimeout(timer);
    timer = window.setTimeout(() => {
      if (copyBtn) copyBtn.textContent = idle;
      if (status) status.textContent = '';
    }, 2000);
  };
  const handle = (outcome: ShareOutcome, fromHero = false) => {
    if (outcome === 'copied') confirm();
    else if (outcome === 'manual') {
      // From the hero the Share block is far below: bring the input into view.
      if (fromHero) document.getElementById('partager')?.scrollIntoView({ block: 'center' });
      showManual();
    }
  };

  copyBtn?.addEventListener('click', async () => handle(await copy(navigator, SHARE_URL)));
  primary?.addEventListener('click', async (e) => {
    if (!navigator.share) return; // desktop: the anchor scrolls to #partager
    e.preventDefault();
    handle(await sharePage(navigator, SHARE_URL, SHARE_TEXT), true);
  });
}
