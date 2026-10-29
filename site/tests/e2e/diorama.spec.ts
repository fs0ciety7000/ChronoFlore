import { existsSync } from 'node:fs';
import { chromium, expect, test, type Browser, type Page } from '@playwright/test';

// Same browser resolution as playwright.config.ts: overriding launchOptions
// replaces the whole object, so the fallback path has to be repeated.
const fallback = process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium';
const executablePath = existsSync(chromium.executablePath()) ? undefined : existsSync(fallback) ? fallback : undefined;
const WEBGL_ARGS = ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'];

// Each group needs its own browser flags, which test.use({ launchOptions })
// cannot set per describe, so these tests launch their own browser.
async function openPage(args: string[], options: { reducedMotion?: 'reduce' } = {}): Promise<{ browser: Browser; page: Page }> {
  const browser = await chromium.launch({ executablePath, args });
  const page = await browser.newPage({
    baseURL: test.info().project.use.baseURL,
    viewport: { width: 1440, height: 900 },
    ...options,
  });
  return { browser, page };
}

function collectErrors(page: Page): string[] {
  const errors: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') errors.push(msg.text());
  });
  page.on('pageerror', (err) => errors.push(err.message));
  return errors;
}

test.describe('with WebGL', () => {
  test('swaps the poster for the live diorama', async () => {
    const { browser, page } = await openPage(WEBGL_ARGS);
    const errors = collectErrors(page);
    await page.goto('/');
    const diorama = page.locator('#diorama');
    await expect(diorama).toHaveAttribute('data-state', 'live', { timeout: 10_000 });
    const canvas = diorama.locator('canvas');
    await expect(canvas).toHaveCount(1);
    await expect(canvas).toHaveAttribute('aria-hidden', 'true');
    // Scroll through the night and back to the top: still live, no errors.
    for (const f of [0.4, 0.78, 1, 0]) {
      await page.evaluate((frac) => {
        const max = document.documentElement.scrollHeight - innerHeight;
        scrollTo({ top: max * frac, behavior: 'instant' });
      }, f);
      await page.waitForTimeout(150);
    }
    await page.mouse.move(900, 450);
    await page.mouse.move(1000, 500);
    await page.waitForTimeout(200);
    await expect(diorama).toHaveAttribute('data-state', 'live');
    expect(errors).toEqual([]);
    await browser.close();
  });

  test('reads hero text on the page colour over the live scene', async () => {
    const { browser, page } = await openPage(WEBGL_ARGS);
    await page.goto('/');
    await expect(page.locator('#diorama')).toHaveAttribute('data-state', 'live', { timeout: 10_000 });
    await page.waitForTimeout(800); // canvas fade-in
    const { bg, points } = await page.evaluate(() => {
      const r = document.querySelector('.hero__text')!.getBoundingClientRect();
      const y = r.top + r.height / 2;
      return {
        bg: getComputedStyle(document.documentElement).getPropertyValue('--bg').trim(),
        points: [
          [r.right + 6, y],
          [r.right - 4, r.top + 4],
          [r.left + r.width / 2, r.bottom + 6],
        ],
      };
    });
    const want = [1, 3, 5].map((i) => parseInt(bg.slice(i, i + 2), 16));
    for (const [x, y] of points) {
      const png = await page.screenshot({ clip: { x: Math.round(x), y: Math.round(y), width: 1, height: 1 } });
      const px = await page.evaluate(async (b64) => {
        const img = new Image();
        img.src = `data:image/png;base64,${b64}`;
        await img.decode();
        const c = document.createElement('canvas').getContext('2d')!;
        c.drawImage(img, 0, 0);
        return [...c.getImageData(0, 0, 1, 1).data.slice(0, 3)];
      }, png.toString('base64'));
      px.forEach((v, i) => expect(Math.abs(v - want[i]), `pixel ${x},${y} = ${px} vs ${bg}`).toBeLessThanOrEqual(3));
    }
    await browser.close();
  });

  test('keeps the poster when WebGL context is lost', async () => {
    const { browser, page } = await openPage(WEBGL_ARGS);
    await page.goto('/');
    const diorama = page.locator('#diorama');
    await expect(diorama).toHaveAttribute('data-state', 'live', { timeout: 10_000 });
    await page.evaluate(() => {
      const gl = document.querySelector<HTMLCanvasElement>('#diorama canvas')!.getContext('webgl2');
      gl?.getExtension('WEBGL_lose_context')?.loseContext();
    });
    await expect(diorama).toHaveAttribute('data-state', 'poster');
    await browser.close();
  });
});

test.describe('without WebGL', () => {
  test('stays on the poster without errors', async () => {
    const { browser, page } = await openPage(['--disable-webgl', '--disable-3d-apis']);
    const errors = collectErrors(page);
    await page.goto('/');
    await page.waitForTimeout(2500); // past the idle callback / 1 s fallback
    await expect(page.locator('#diorama')).toHaveAttribute('data-state', 'poster');
    await expect(page.locator('#diorama img')).toBeVisible();
    await expect(page.locator('#diorama canvas')).toHaveCount(0);
    expect(errors).toEqual([]);
    await browser.close();
  });
});

test.describe('reduced motion', () => {
  test('never creates a canvas', async () => {
    const { browser, page } = await openPage(WEBGL_ARGS, { reducedMotion: 'reduce' });
    await page.goto('/');
    await page.waitForTimeout(2500);
    await expect(page.locator('canvas')).toHaveCount(0);
    await expect(page.locator('#diorama')).toHaveAttribute('data-state', 'poster');
    await browser.close();
  });
});
