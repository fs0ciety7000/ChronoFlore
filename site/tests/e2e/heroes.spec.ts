import { existsSync } from 'node:fs';
import { chromium, expect, test, type Page } from '@playwright/test';

// The heroine and the companion: Planche II portrait, the new Planche III,
// and the duo strolling on the diorama island.

const HEROINE_LABEL = "L'héroïne en 3D : peau foncée, longues tresses, lunettes roses, haut à rayures";
const COMPANION_LABEL = 'Le compagnon en 3D : casquette de tweed grise, veste kaki, barbe courte';
const COMPANION_P1 =
  "Casquette de tweed, veste kaki, sourire en coin : il n'est pas réel, et il le sait. C'est une figure de son rêve, quelqu'un qu'elle a fait venir dans sa nuit pour ne pas la traverser seule.";
const COMPANION_P2 = 'Joue-le seul, ou à deux en coop locale : la nuit, les pétales et l\'herbier restent les siens.';

const heroine = (page: Page) => page.locator('#chasseuse [data-portrait="heroine"]');
const companion = (page: Page) => page.locator('#compagnon [data-portrait="companion"]');

test.describe('characters: page structure', () => {
  test('adds Planche III « Le compagnon » with the exact copy', async ({ page }) => {
    await page.goto('/');
    const section = page.locator('section#compagnon');
    await expect(section).toHaveCount(1);
    await expect(section).toHaveAttribute('data-scene', 'compagnon');
    await expect(section.locator('.plate-heading__caption')).toHaveText('Planche III');
    await expect(section.locator('h2')).toHaveText('Le compagnon');
    const paragraphs = section.locator('p:not(.plate-heading__caption)');
    await expect(paragraphs).toHaveText([COMPANION_P1, COMPANION_P2]);
  });

  test('renumbers the plates and orders the sections', async ({ page }) => {
    await page.goto('/');
    const plates = await page.locator('main section').evaluateAll((sections) =>
      sections
        .map((s) => [s.id, s.querySelector('.plate-heading__caption')?.textContent?.trim()])
        .filter(([, caption]) => caption),
    );
    expect(plates).toEqual([
      ['reve', 'Planche I'],
      ['chasseuse', 'Planche II'],
      ['compagnon', 'Planche III'],
      ['outils', 'Planche IV'],
      ['herbier', 'Planche V'],
    ]);
  });

  test('links « Le compagnon » in the navigation after « La chasseuse »', async ({ page }) => {
    await page.goto('/');
    const links = await page
      .locator('.site-header__nav a')
      .evaluateAll((as) => as.map((a) => [a.getAttribute('href'), a.textContent!.trim()]));
    expect(links).toEqual([
      ['#reve', 'Le rêve'],
      ['#chasseuse', 'La chasseuse'],
      ['#compagnon', 'Le compagnon'],
      ['#outils', 'Les outils'],
      ['#herbier', "L'herbier"],
      ['#partager', 'Partager'],
    ]);
  });

  test('labels both portraits and ships a still image of each model', async ({ page }) => {
    await page.goto('/');
    for (const [card, label] of [
      [heroine(page), HEROINE_LABEL],
      [companion(page), COMPANION_LABEL],
    ] as const) {
      await expect(card).toHaveAttribute('role', 'img');
      await expect(card).toHaveAttribute('aria-label', label);
      const img = card.locator('img');
      await expect(img).toHaveAttribute('alt', label);
      await expect(img).toHaveAttribute('src', /\.webp$/);
      await img.scrollIntoViewIfNeeded();
      await expect.poll(() => img.evaluate((i: HTMLImageElement) => i.complete && i.naturalWidth)).toBeGreaterThan(0);
    }
    // No more placeholder text.
    await expect(page.getByText("[Rendu 3D de l'héroïne — à venir]")).toHaveCount(0);
  });

  test('mirrors the layout: heroine portrait left, companion portrait right (desktop)', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto('/');
    const left = async (sel: string) => (await page.locator(sel).boundingBox())!.x;
    expect(await left('#chasseuse [data-portrait]')).toBeLessThan(await left('#chasseuse h2'));
    expect(await left('#compagnon [data-portrait]')).toBeGreaterThan(await left('#compagnon h2'));
  });
});

// Live 3D: same browser setup as diorama.spec.ts (own browser per group).
const fallback = process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium';
const executablePath = existsSync(chromium.executablePath()) ? undefined : existsSync(fallback) ? fallback : undefined;
const WEBGL_ARGS = ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'];
const NO_WEBGL_ARGS = ['--disable-webgl', '--disable-3d-apis'];

type Options = { reducedMotion?: 'reduce'; viewport?: { width: number; height: number } };

async function withPage(args: string[], fn: (page: Page) => Promise<void>, options: Options = {}) {
  const browser = await chromium.launch({ executablePath, args });
  try {
    const page = await browser.newPage({
      baseURL: test.info().project.use.baseURL,
      viewport: options.viewport ?? { width: 1440, height: 900 },
      reducedMotion: options.reducedMotion,
    });
    // Count every WebGL context the page creates (the env probe loses its own at once).
    await page.addInitScript(() => {
      const contexts: WebGLRenderingContext[] = [];
      (window as unknown as { __gl: WebGLRenderingContext[] }).__gl = contexts;
      const original = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function (this: HTMLCanvasElement, type: string, ...rest: unknown[]) {
        const ctx = (original as (...a: unknown[]) => unknown).call(this, type, ...rest);
        if (ctx && type.startsWith('webgl') && !contexts.includes(ctx as WebGLRenderingContext)) contexts.push(ctx as WebGLRenderingContext);
        return ctx;
      } as typeof original;
    });
    await fn(page);
  } finally {
    await browser.close();
  }
}

/**
 * Console errors and page errors. `aborted` holds the URLs a test aborts on
 * purpose: only the browser's own "Failed to load resource" line for one of
 * those is ignored; any other failed load still counts.
 */
function collectErrors(page: Page, aborted: Set<string> = new Set()): string[] {
  const errors: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() !== 'error') return;
    if (/Failed to load resource/.test(msg.text()) && aborted.has(msg.location().url)) return;
    errors.push(`${msg.text()} ${msg.location().url}`);
  });
  page.on('pageerror', (err) => errors.push(err.message));
  return errors;
}

const liveContexts = (page: Page) =>
  page.evaluate(() => (window as unknown as { __gl: WebGLRenderingContext[] }).__gl.filter((gl) => !gl.isContextLost()).length);

test.describe('characters with WebGL', () => {
  test('portraits go live, render only on screen, and swing on hover and focus', async () => {
    test.setTimeout(90_000);
    await withPage(WEBGL_ARGS, async (page) => {
      const errors = collectErrors(page);
      await page.goto('/');
      await page.locator('#chasseuse').scrollIntoViewIfNeeded();
      const card = heroine(page);
      await expect(card).toHaveAttribute('data-state', 'live', { timeout: 20_000 });
      const canvas = card.locator('canvas');
      await expect(canvas).toHaveCount(1);
      await expect(canvas).toHaveAttribute('aria-hidden', 'true');
      await expect(card).toHaveAttribute('data-playing', 'true');
      await expect(card).toHaveAttribute('data-action', 'Idle');
      await expect(card).toHaveAttribute('tabindex', '0');

      // Hover: the net swing, then back to idle.
      await card.hover();
      await expect(card).toHaveAttribute('data-action', 'Swing');
      await expect(card).toHaveAttribute('data-action', 'Idle', { timeout: 5000 });

      // Keyboard focus plays it too.
      await page.mouse.move(5, 5);
      await card.focus();
      await expect(card).toHaveAttribute('data-action', 'Swing');
      await expect(card).toHaveAttribute('data-action', 'Idle', { timeout: 5000 });

      await page.locator('#compagnon').scrollIntoViewIfNeeded();
      await expect(companion(page)).toHaveAttribute('data-state', 'live', { timeout: 20_000 });
      await expect(companion(page)).toHaveAttribute('data-playing', 'true');

      // Off screen: no portrait renders.
      await page.evaluate(() => scrollTo({ top: 0, behavior: 'instant' }));
      await expect(heroine(page)).toHaveAttribute('data-playing', 'false');
      await expect(companion(page)).toHaveAttribute('data-playing', 'false');
      expect(errors).toEqual([]);
    });
  });

  test('never holds more than 2 WebGL contexts, and the duo walks on the island', async () => {
    test.setTimeout(90_000);
    await withPage(WEBGL_ARGS, async (page) => {
      await page.goto('/');
      const diorama = page.locator('#diorama');
      await expect(diorama).toHaveAttribute('data-state', 'live', { timeout: 20_000 });
      await expect(diorama).toHaveAttribute('data-duo', '2', { timeout: 20_000 });
      for (const id of ['chasseuse', 'compagnon', 'outils', 'herbier', 'partager']) {
        await page.locator(`#${id}`).scrollIntoViewIfNeeded();
        await page.waitForTimeout(300);
        expect(await liveContexts(page), `live WebGL contexts at #${id}`).toBeLessThanOrEqual(2);
      }
      await expect(heroine(page)).toHaveAttribute('data-state', 'live');
      await expect(companion(page)).toHaveAttribute('data-state', 'live');
      expect(await liveContexts(page)).toBe(2);
      // Only the diorama canvas and one shared portrait renderer hold WebGL.
      const webglCanvases = await page.evaluate(
        () => [...document.querySelectorAll('canvas')].filter((c) => (window as unknown as { __gl: WebGLRenderingContext[] }).__gl.some((gl) => gl.canvas === c && !gl.isContextLost())).length,
      );
      expect(webglCanvases).toBeLessThanOrEqual(2);
    });
  });

  test('falls back to the still images when the portrait context is lost', async () => {
    test.setTimeout(60_000);
    await withPage(WEBGL_ARGS, async (page) => {
      const errors = collectErrors(page);
      await page.goto('/');
      await page.locator('#chasseuse').scrollIntoViewIfNeeded();
      await expect(heroine(page)).toHaveAttribute('data-state', 'live', { timeout: 20_000 });
      await page.evaluate(() => {
        const gls = (window as unknown as { __gl: WebGLRenderingContext[] }).__gl;
        const diorama = document.querySelector('#diorama canvas');
        const gl = gls.find((g) => g.canvas !== diorama && !g.isContextLost());
        gl?.getExtension('WEBGL_lose_context')?.loseContext();
      });
      await expect(heroine(page)).toHaveAttribute('data-state', 'still');
      await expect(heroine(page).locator('canvas')).toHaveCount(0);
      await expect(heroine(page).locator('img')).toBeVisible();
      await expect(heroine(page)).not.toHaveAttribute('tabindex', /.*/);
      await expect(companion(page)).toHaveAttribute('data-state', 'still');
      // Only the diorama's context is left.
      await expect.poll(() => liveContexts(page)).toBe(1);
      expect(errors).toEqual([]);
    });
  });

  test('keeps the stills and an island without the duo when the character models fail', async () => {
    test.setTimeout(60_000);
    await withPage(WEBGL_ARGS, async (page) => {
      const aborted = new Set<string>();
      const errors = collectErrors(page, aborted);
      await page.route('**/models/custom/*.glb', (route) => {
        aborted.add(route.request().url());
        return route.abort();
      });
      await page.goto('/');
      const diorama = page.locator('#diorama');
      await expect(diorama).toHaveAttribute('data-state', 'live', { timeout: 20_000 });
      await expect(diorama).toHaveAttribute('data-duo', '0', { timeout: 20_000 });
      const created = () => page.evaluate(() => (window as unknown as { __gl: unknown[] }).__gl.length);
      const before = await created(); // env probe + diorama
      await page.locator('#chasseuse').scrollIntoViewIfNeeded();
      // The portraits' renderer is created (one more context), then released when the load fails.
      await expect.poll(created, { timeout: 20_000 }).toBe(before + 1);
      await expect.poll(() => liveContexts(page), { timeout: 10_000 }).toBe(1);
      for (const card of [heroine(page), companion(page)]) {
        await expect(card).toHaveAttribute('data-state', 'still');
        await expect(card.locator('canvas')).toHaveCount(0);
        await expect(card).not.toHaveAttribute('tabindex', /.*/);
      }
      await expect(heroine(page).locator('img')).toBeVisible();
      await expect(diorama).toHaveAttribute('data-state', 'live');
      expect(errors).toEqual([]);
    });
  });
});

test.describe('characters without 3D', () => {
  test('without WebGL: still images, no canvas, no errors', async () => {
    await withPage(NO_WEBGL_ARGS, async (page) => {
      const errors = collectErrors(page);
      await page.goto('/', { waitUntil: 'networkidle' });
      await page.locator('#compagnon').scrollIntoViewIfNeeded();
      await expect.poll(() => liveContexts(page), { timeout: 5000 }).toBe(0);
      for (const card of [heroine(page), companion(page)]) {
        await expect(card).toHaveAttribute('data-state', 'still');
        await expect(card.locator('canvas')).toHaveCount(0);
        await expect(card).not.toHaveAttribute('tabindex', /.*/);
      }
      await expect(companion(page).locator('img')).toBeVisible();
      expect(errors).toEqual([]);
    });
  });

  test('reduced motion: still images, no canvas at all', async () => {
    await withPage(
      WEBGL_ARGS,
      async (page) => {
        await page.goto('/', { waitUntil: 'networkidle' });
        await page.locator('#chasseuse').scrollIntoViewIfNeeded();
        await expect.poll(() => liveContexts(page), { timeout: 5000 }).toBe(0);
        await expect(page.locator('canvas')).toHaveCount(0);
        await expect(heroine(page)).toHaveAttribute('data-state', 'still');
        await expect(heroine(page).locator('img')).toBeVisible();
        expect(await liveContexts(page)).toBe(0);
      },
      { reducedMotion: 'reduce' },
    );
  });
});
