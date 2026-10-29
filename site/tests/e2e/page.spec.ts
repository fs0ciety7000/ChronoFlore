import { expect, test } from '@playwright/test';

const ANCHORS = ['top', 'reve', 'chasseuse', 'compagnon', 'outils', 'herbier', 'partager'];

test.describe('static one-page layout', () => {
  test('renders the opening, all sections and the portraits', async ({ page }) => {
    await page.goto('/');

    await expect(page.locator('html')).toHaveAttribute('lang', 'fr');
    await expect(page.locator('h1')).toHaveText('Huit heures de sommeil. Toute une flore à capturer.');

    for (const id of ANCHORS) {
      const section = page.locator(`section#${id}`);
      await expect(section, `#${id}`).toHaveCount(1);
      await expect(section).toHaveAttribute('data-scene', /.*/);
    }

    await expect(page.locator('[data-specimen]')).toHaveCount(12);
    await expect(page.locator('#chasseuse [data-portrait="heroine"]')).toHaveCount(1);
    await expect(page.locator('#compagnon [data-portrait="companion"]')).toHaveCount(1);

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

  test('hero links to the playable game at /jouer/', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('.hero .actions a[href="/jouer/"]')).toHaveText('Jouer au prototype');
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

const BESTIARY = [
  ['001', 'Rêvette', 'joie légère', 'commune', 'Rêvette, plante de la joie légère'],
  ['002', 'Nostalgerbe', 'nostalgie', 'commune', 'Nostalgerbe, plante de la nostalgie'],
  ['003', 'Câlinette', 'tendresse', 'commune', 'Câlinette, plante de la tendresse'],
  ['004', 'Souffloine', 'insouciance', 'peu commune', "Souffloine, plante de l'insouciance"],
  ['005', 'Timidelle', 'timidité', 'peu commune', 'Timidelle, plante de la timidité'],
  ['006', 'Mélancolys', 'mélancolie', 'peu commune', 'Mélancolys, plante de la mélancolie'],
  ['007', 'Lumiole', 'espoir', 'rare', "Lumiole, plante de l'espoir"],
  ['008', 'Ronce-Angoisse', 'angoisse', 'commune', "Ronce-Angoisse, plante de l'angoisse"],
  ['009', 'Croque-Colère', 'colère', 'peu commune', 'Croque-Colère, plante de la colère'],
  ['010', 'Lierre-Jalousie', 'jalousie', 'peu commune', 'Lierre-Jalousie, plante de la jalousie'],
  ['011', 'Ortie-Regret', 'regret', 'rare', 'Ortie-Regret, plante du regret'],
  ['012', 'Champi-Panique', 'panique', 'rare', 'Champi-Panique, plante de la panique'],
] as const;

test.describe('herbarium bestiary', () => {
  test('lists the 12 plants in order, 7 gentle then 5 hostile', async ({ page }) => {
    await page.goto('/');
    const herbier = page.locator('#herbier');
    await expect(herbier.locator('.herbarium__note')).toHaveText('Textes provisoires — le bestiaire pousse avec le jeu');
    await expect(herbier).not.toContainText("Espèces d'exemple");
    await expect(herbier.locator('svg.plate__drawing')).toHaveCount(0);

    const gentle = herbier.locator('[data-group="gentle"]');
    const hostile = herbier.locator('[data-group="hostile"]');
    await expect(gentle.locator('h3')).toHaveText('Les douces — à cueillir au filet');
    await expect(hostile.locator('h3')).toHaveText('Les monstres plantes — à endormir avant de les cueillir');
    await expect(gentle.locator('[data-specimen]')).toHaveCount(7);
    await expect(hostile.locator('[data-specimen]')).toHaveCount(5);
    await expect(hostile.locator('[data-specimen][data-hostile]')).toHaveCount(5);
    await expect(gentle.locator('[data-hostile]')).toHaveCount(0);

    const cards = herbier.locator('[data-specimen]');
    for (const [i, [n, name, emotion, rarity]] of BESTIARY.entries()) {
      const card = cards.nth(i);
      await expect(card.locator('.plate__number')).toHaveText(`N° ${n}`);
      await expect(card.locator('h4')).toHaveText(name);
      await expect(card.locator('.plate__emotion')).toHaveText(emotion);
      await expect(card.locator('.plate__rarity')).toHaveText(rarity);
    }
    await expect(cards.nth(0).locator('.plate__hour')).toHaveText('dès la tombée du sommeil');
    await expect(cards.nth(6).locator('.plate__hour')).toHaveText('dès 4 h');
    await expect(cards.nth(11).locator('.plate__hour')).toHaveText('dès 5 h');
  });

  test('each card has a sized, lazy WebP thumbnail with the right alt', async ({ page }) => {
    await page.goto('/');
    const cards = page.locator('#herbier [data-specimen]');
    for (const [i, [, , , , alt]] of BESTIARY.entries()) {
      const img = cards.nth(i).locator('img');
      await expect(img).toHaveAttribute('alt', alt);
      await expect(img).toHaveAttribute('width', /^\d+$/);
      await expect(img).toHaveAttribute('height', /^\d+$/);
      await expect(img).toHaveAttribute('loading', 'lazy');
      await expect(img).toHaveAttribute('src', /^\/herbier\/[a-z_]+\.webp$/);
    }
  });

  test('thumbnails are served as small WebP files', async ({ page }) => {
    await page.goto('/');
    const srcs = await page.locator('#herbier img').evaluateAll((is) => is.map((i) => i.getAttribute('src')!));
    expect(srcs).toHaveLength(12);
    for (const src of srcs) {
      const res = await page.request.get(src);
      expect(res.status(), src).toBe(200);
      expect(res.headers()['content-type'], src).toContain('image/webp');
      expect((await res.body()).length, src).toBeLessThanOrEqual(15 * 1024);
    }
  });

  test('images reserve their space: no layout shift while they load', async ({ page }) => {
    await page.goto('/');
    const boxes = await page.locator('#herbier img').evaluateAll((is) =>
      is.map((i) => {
        const r = i.getBoundingClientRect();
        return { w: i.getAttribute('width'), h: i.getAttribute('height'), rw: r.width, rh: r.height };
      }),
    );
    for (const { w, h, rw, rh } of boxes) {
      expect(Number(w)).toBeGreaterThan(0);
      expect(w).toBe(h); // square thumbnails, same aspect as the files
      expect(Math.abs(rw - rh)).toBeLessThanOrEqual(1);
    }
  });

  test('"Lire la page" opens with the keyboard and shows the fragment', async ({ page }) => {
    await page.goto('/');
    const card = page.locator('#herbier [data-specimen]').first();
    const details = card.locator('details');
    await expect(details).not.toHaveAttribute('open', '');
    await expect(details.locator('summary')).toHaveText('Lire la page');
    await expect(details.locator('p')).toBeHidden();
    await details.locator('summary').focus();
    await page.keyboard.press('Enter');
    await expect(details).toHaveAttribute('open', '');
    await expect(details.locator('p')).toBeVisible();
    await expect(details.locator('p')).toContainText("Une petite joie qui ne pesait rien");
    await expect(details.locator('p')).not.toContainText('provisoire');
    await page.keyboard.press('Space');
    await expect(details).not.toHaveAttribute('open', '');
  });

  test('keeps the grid inside the viewport on a phone', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/');
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
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
    const alt =
      'Île-diorama flottante au crépuscule, logo ChronoFlore et le titre Huit heures de sommeil. Toute une flore à capturer.';
    expect(await meta('meta[property="og:image:alt"]')).toBe(alt);
    expect(await meta('meta[name="twitter:image:alt"]')).toBe(alt);
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

  test('without JavaScript, shows the readonly link instead of an inert copy button', async ({ browser }) => {
    const context = await browser.newContext({ javaScriptEnabled: false });
    const page = await context.newPage();
    await page.goto('/');
    await expect(page.locator('[data-copy-link]')).toBeHidden();
    const input = page.locator('#partager input[readonly]');
    await expect(input).toBeVisible();
    await expect(input).toHaveValue('https://chronoflore.cardormedia.com/');
    await context.close();
  });

  test('with JavaScript, swaps the readonly link for the copy button', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('[data-copy-link]')).toBeVisible();
    await expect(page.locator('#partager input[readonly]')).toBeHidden();
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
