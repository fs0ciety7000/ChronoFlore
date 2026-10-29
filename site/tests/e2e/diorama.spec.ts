import { existsSync } from 'node:fs';
import { chromium, expect, test, type Page } from '@playwright/test';

// Same browser resolution as playwright.config.ts. Each group needs its own
// browser flags, which test.use({ launchOptions }) cannot set per describe, so
// these tests launch (and always close) their own browser.
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
    await fn(page);
  } finally {
    await browser.close();
  }
}

function collectErrors(page: Page): string[] {
  const errors: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') errors.push(msg.text());
  });
  page.on('pageerror', (err) => errors.push(err.message));
  return errors;
}

async function scrollToFraction(page: Page, f: number) {
  await page.evaluate((frac) => {
    const max = document.documentElement.scrollHeight - innerHeight;
    scrollTo({ top: max * frac, behavior: 'instant' });
  }, f);
}

async function pixel(page: Page, x: number, y: number): Promise<number[]> {
  const png = await page.screenshot({ clip: { x: Math.round(x), y: Math.round(y), width: 1, height: 1 } });
  return page.evaluate(async (b64) => {
    const img = new Image();
    img.src = `data:image/png;base64,${b64}`;
    await img.decode();
    const c = document.createElement('canvas').getContext('2d')!;
    c.drawImage(img, 0, 0);
    return [...c.getImageData(0, 0, 1, 1).data.slice(0, 3)];
  }, png.toString('base64'));
}

const hexRgb = (hex: string) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));

test.describe('with WebGL', () => {
  test('swaps the poster for the live diorama', async () => {
    await withPage(WEBGL_ARGS, async (page) => {
      const errors = collectErrors(page);
      await page.goto('/');
      const diorama = page.locator('#diorama');
      await expect(diorama).toHaveAttribute('data-state', 'live', { timeout: 10_000 });
      const canvas = diorama.locator('canvas');
      await expect(canvas).toHaveCount(1);
      await expect(canvas).toHaveAttribute('aria-hidden', 'true');
      // Scroll through the night and back to the top: still live, no errors.
      for (const f of [0.4, 0.78, 1, 0]) {
        await scrollToFraction(page, f);
        await page.waitForTimeout(150);
      }
      await page.mouse.move(900, 450);
      await page.mouse.move(1000, 500);
      await page.waitForTimeout(200);
      await expect(diorama).toHaveAttribute('data-state', 'live');
      expect(errors).toEqual([]);
    });
  });

  test('keeps the copy clear of the island, which really renders there', async () => {
    await withPage(WEBGL_ARGS, async (page) => {
      await page.goto('/');
      await expect(page.locator('#diorama')).toHaveAttribute('data-state', 'live', { timeout: 10_000 });
      for (const f of [0, 0.4, 0.78, 1]) {
        await scrollToFraction(page, f);
        // Wait until the island has finished gliding (scene smoothing).
        await page.waitForTimeout(2500);
        const { island, bg, overlaps } = await page.evaluate(() => {
          const [x, y, r] = document.getElementById('diorama')!.dataset.island!.split(',').map(Number);
          const texts = [...document.querySelectorAll('main h1, main h2, main h3, main p, footer p')];
          const overlaps = texts
            .map((el) => ({ el, rect: el.getBoundingClientRect() }))
            .filter(({ rect }) => rect.bottom > 0 && rect.top < innerHeight && rect.width > 0)
            // Text on an opaque card (plates, tools, share, countdown band) does not sit on the scene.
            .filter(({ el }) => !el.closest('.plate, .tool, .share__card, .countdown, .hero__kicker'))
            .filter(({ rect }) => {
              const cx = Math.max(rect.left, Math.min(x, rect.right));
              const cy = Math.max(rect.top, Math.min(y, rect.bottom));
              return Math.hypot(cx - x, cy - y) < r;
            })
            .map(({ el }) => el.textContent!.trim().slice(0, 40));
          return {
            island: { x, y, r },
            bg: getComputedStyle(document.documentElement).getPropertyValue('--bg').trim(),
            overlaps,
          };
        });
        expect(overlaps, `text over the island at ${f}`).toEqual([]);
        // The scene shows at the island's centre (not the plain sky colour).
        const px = await pixel(page, island.x, island.y);
        const sky = hexRgb(bg);
        const diff = Math.max(...px.map((v, i) => Math.abs(v - sky[i])));
        expect(diff, `island pixel ${px} vs sky ${bg} at ${f}`).toBeGreaterThan(12);
      }
    });
  });

  test('keeps the poster when WebGL context is lost', async () => {
    await withPage(WEBGL_ARGS, async (page) => {
      await page.goto('/');
      const diorama = page.locator('#diorama');
      await expect(diorama).toHaveAttribute('data-state', 'live', { timeout: 10_000 });
      await page.evaluate(() => {
        const gl = document.querySelector<HTMLCanvasElement>('#diorama canvas')!.getContext('webgl2');
        gl?.getExtension('WEBGL_lose_context')?.loseContext();
      });
      await expect(diorama).toHaveAttribute('data-state', 'poster');
    });
  });

  test('keeps the poster when the models fail to load', async () => {
    await withPage(WEBGL_ARGS, async (page) => {
      const pageErrors: string[] = [];
      const consoleErrors: string[] = [];
      page.on('pageerror', (err) => pageErrors.push(err.message));
      page.on('console', (msg) => {
        // The browser logs its own line for each aborted request; that is not ours.
        if (msg.type() === 'error' && !/Failed to load resource/.test(msg.text())) consoleErrors.push(msg.text());
      });
      await page.route('**/models/**', (route) => route.abort());
      await page.goto('/');
      await page.waitForTimeout(4000);
      await expect(page.locator('#diorama')).toHaveAttribute('data-state', 'poster');
      await expect(page.locator('#diorama canvas')).toHaveCount(0);
      await expect(page.locator('#diorama img')).toBeVisible();
      expect(pageErrors).toEqual([]);
      expect(consoleErrors).toEqual([]);
    });
  });
});

test.describe('without WebGL', () => {
  test('stays on the poster without errors', async () => {
    await withPage(NO_WEBGL_ARGS, async (page) => {
      const errors = collectErrors(page);
      await page.goto('/');
      await page.waitForTimeout(2500); // past the idle callback / 1 s fallback
      await expect(page.locator('#diorama')).toHaveAttribute('data-state', 'poster');
      await expect(page.locator('#diorama img')).toBeVisible();
      await expect(page.locator('#diorama canvas')).toHaveCount(0);
      expect(errors).toEqual([]);
    });
  });
});

test.describe('reduced motion', () => {
  test('never creates a canvas', async () => {
    await withPage(
      WEBGL_ARGS,
      async (page) => {
        await page.goto('/');
        await page.waitForTimeout(2500);
        await expect(page.locator('canvas')).toHaveCount(0);
        await expect(page.locator('#diorama')).toHaveAttribute('data-state', 'poster');
      },
      { reducedMotion: 'reduce' },
    );
  });
});
