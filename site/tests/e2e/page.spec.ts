import { expect, test } from '@playwright/test';

const ANCHORS = ['top', 'reve', 'chasseuse', 'outils', 'herbier', 'partager'];
const HEROINE_PLACEHOLDER = "[Rendu 3D de l'héroïne — à venir]";

test.describe('static one-page layout', () => {
  test('renders the opening, all sections and the placeholders', async ({ page }) => {
    await page.goto('/');

    await expect(page.locator('html')).toHaveAttribute('lang', 'fr');
    await expect(page.locator('h1')).toHaveText('Huit heures de sommeil. Toute une flore à capturer.');

    for (const id of ANCHORS) {
      const section = page.locator(`section#${id}`);
      await expect(section, `#${id}`).toHaveCount(1);
      await expect(section).toHaveAttribute('data-scene', /.*/);
    }

    await expect(page.locator('[data-specimen]')).toHaveCount(4);
    await expect(page.locator('#chasseuse [data-heroine]')).toHaveText(HEROINE_PLACEHOLDER);

    await expect(page.locator('output#countdown')).toHaveText('00:00:00');
    // Served as the poster; the live 3D scene may already have replaced it.
    const html = await (await page.request.get('/')).text();
    expect(html).toMatch(/<div id="diorama"[^>]*data-state="poster"/);
    const diorama = page.locator('div#diorama');
    await expect(diorama).toHaveAttribute('data-state', /^(poster|live)$/);
    await expect(diorama.locator('img[src="/poster.webp"]')).toHaveAttribute('alt', '');
  });

  test('starts with the day palette on :root', async ({ page }) => {
    await page.goto('/');
    const vars = await page.evaluate(() => {
      const s = getComputedStyle(document.documentElement);
      return ['--bg', '--ink', '--accent', '--surface', '--progress'].map((v) =>
        s.getPropertyValue(v).trim().toLowerCase(),
      );
    });
    expect(vars).toEqual(['#f6f1e7', '#3b3350', '#f4b9c8', '#fffdf8', '0']);
  });

  test('has no horizontal overflow at 360x740', async ({ page }) => {
    await page.setViewportSize({ width: 360, height: 740 });
    await page.goto('/');
    const scrollWidth = await page.evaluate(() => document.documentElement.scrollWidth);
    expect(scrollWidth).toBeLessThanOrEqual(360);
  });

  test('makes no Google Fonts request and logs no console error', async ({ page }) => {
    const fontRequests: string[] = [];
    const errors: string[] = [];
    page.on('request', (req) => {
      if (/fonts\.(googleapis|gstatic)\.com/.test(req.url())) fontRequests.push(req.url());
    });
    page.on('console', (msg) => {
      if (msg.type() === 'error') errors.push(msg.text());
    });
    page.on('pageerror', (err) => errors.push(err.message));

    await page.goto('/', { waitUntil: 'networkidle' });
    await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
    await page.waitForLoadState('networkidle');

    expect(fontRequests).toEqual([]);
    expect(errors).toEqual([]);
  });

  test('keyboard: Tab reaches "Le rêve" then "Partager le rêve"', async ({ page }) => {
    await page.goto('/');
    const focused = () =>
      page.evaluate(() => (document.activeElement as HTMLElement | null)?.innerText.trim() ?? '');

    const seen: string[] = [];
    for (let i = 0; i < 20 && !seen.includes('Partager le rêve'); i++) {
      await page.keyboard.press('Tab');
      seen.push(await focused());
    }
    const reve = seen.indexOf('Le rêve');
    const share = seen.indexOf('Partager le rêve');
    expect(reve, `focus order: ${seen.join(' | ')}`).toBeGreaterThanOrEqual(0);
    expect(share).toBeGreaterThan(reve);
  });
});

test.describe('share and metadata', () => {
  test('exposes Open Graph, Twitter and icon metadata', async ({ page }) => {
    await page.goto('/');
    const meta = (sel: string) => page.locator(sel).getAttribute('content');
    expect(await meta('meta[property="og:title"]')).toContain('ChronoFlore');
    expect(await meta('meta[property="og:description"]')).toBeTruthy();
    expect(await meta('meta[property="og:image"]')).toBe('https://chronoflore.cardormedia.com/og.png');
    expect(await meta('meta[name="twitter:card"]')).toBe('summary_large_image');
    await expect(page.locator('link[rel="icon"][type="image/svg+xml"]')).toHaveAttribute('href', '/favicon.svg');
    await expect(page.locator('link[rel="icon"][href="/favicon.ico"]')).toHaveCount(1);
  });

  test('share links carry encoded URL and text', async ({ page }) => {
    await page.goto('/');
    const hrefs = await page.locator('#partager a.btn--soft').evaluateAll((as) => as.map((a) => (a as HTMLAnchorElement).href));
    expect(hrefs.some((h) => h.startsWith('https://bsky.app/intent/compose?text=') && h.includes('%C3%A0'))).toBe(true);
    expect(hrefs.some((h) => h.startsWith('https://x.com/intent/post?text=') && h.includes('&url=https%3A%2F%2Fchronoflore'))).toBe(true);
    expect(hrefs.some((h) => h.startsWith('https://www.facebook.com/sharer/sharer.php?u=https%3A%2F%2Fchronoflore'))).toBe(true);
  });

  test('"Copier le lien" copies and confirms for 2 s', async ({ page, context }) => {
    await context.grantPermissions(['clipboard-read', 'clipboard-write']);
    await page.goto('/');
    const btn = page.locator('[data-copy-link]');
    await btn.click();
    await expect(btn).toHaveText('Lien copié');
    await expect(page.locator('[role="status"][data-share-status]')).toHaveText('Lien copié');
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe('https://chronoflore.cardormedia.com/');
    await expect(btn).toHaveText('Copier le lien', { timeout: 4000 });
    await expect(page.locator('[data-share-status]')).toHaveText('');
  });

  test('without clipboard, shows a preselected readonly input', async ({ page }) => {
    await page.addInitScript(() => {
      Object.defineProperty(navigator, 'clipboard', { value: undefined, configurable: true });
    });
    await page.goto('/');
    await page.locator('[data-copy-link]').click();
    const input = page.locator('#partager input[readonly]');
    await expect(input).toBeVisible();
    await expect(input).toHaveValue('https://chronoflore.cardormedia.com/');
    expect(await input.evaluate((i: HTMLInputElement) => i.selectionEnd! - i.selectionStart!)).toBe(36);
  });

  test('"Partager le rêve" calls navigator.share when available', async ({ page }) => {
    await page.addInitScript(() => {
      (window as any).__shared = null;
      Object.defineProperty(navigator, 'share', {
        value: (d: unknown) => ((window as any).__shared = d, Promise.resolve()),
        configurable: true,
      });
    });
    await page.goto('/');
    await page.locator('[data-share-primary]').click();
    expect(await page.evaluate(() => (window as any).__shared)).toMatchObject({
      url: 'https://chronoflore.cardormedia.com/',
    });
  });

  test('hero button without share or clipboard reveals the input in view', async ({ page }) => {
    await page.addInitScript(() => {
      Object.defineProperty(navigator, 'clipboard', { value: undefined, configurable: true });
      Object.defineProperty(navigator, 'share', { value: () => Promise.reject(new Error('x')), configurable: true });
    });
    await page.goto('/');
    await page.locator('[data-share-primary]').click();
    const input = page.locator('#partager input[readonly]');
    await expect(input).toBeVisible();
    await expect(input).toBeInViewport();
  });

  test('hero button announces a clipboard copy in the live region', async ({ page, context }) => {
    await context.grantPermissions(['clipboard-read', 'clipboard-write']);
    await page.addInitScript(() => {
      Object.defineProperty(navigator, 'share', { value: () => Promise.reject(new Error('x')), configurable: true });
    });
    await page.goto('/');
    await page.locator('[data-share-primary]').click();
    await expect(page.locator('[data-share-status]')).toHaveText('Lien copié');
  });
});
