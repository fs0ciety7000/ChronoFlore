import { expect, test } from '@playwright/test';

const ANCHORS = ['top', 'reve', 'chasseuse', 'outils', 'herbier', 'partager'];
const HEROINE_PLACEHOLDER = "[Rendu 3D de l'héroïne — à venir]";

test.describe('static one-page layout', () => {
  test('renders the opening, all sections and the placeholders', async ({ page }) => {
    await page.goto('/');

    await expect(page.locator('html')).toHaveAttribute('lang', 'fr');
    await expect(page.locator('h1')).toHaveText('Deux heures de sommeil. Toute une flore à capturer.');

    for (const id of ANCHORS) {
      const section = page.locator(`section#${id}`);
      await expect(section, `#${id}`).toHaveCount(1);
      await expect(section).toHaveAttribute('data-scene', /.*/);
    }

    await expect(page.locator('[data-specimen]')).toHaveCount(4);
    await expect(page.locator('#chasseuse [data-heroine]')).toHaveText(HEROINE_PLACEHOLDER);

    await expect(page.locator('output#countdown')).toHaveText('02:00:00');
    const diorama = page.locator('div#diorama');
    await expect(diorama).toHaveAttribute('data-state', 'poster');
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
