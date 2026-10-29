import { expect, test, type Page } from '@playwright/test';

const bgOf = (page: Page) =>
  page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--bg').trim().toLowerCase());

/** Jump (no smooth scrolling) to a fraction of the scrollable height. */
async function scrollToFraction(page: Page, f: number) {
  await page.evaluate((frac) => {
    const max = document.documentElement.scrollHeight - window.innerHeight;
    window.scrollTo({ top: max * frac, behavior: 'instant' });
  }, f);
}

/** WCAG contrast of an element's computed text colour against the live --bg. */
async function textContrast(page: Page, selector: string): Promise<number> {
  return page.evaluate((sel) => {
    const rgb = (css: string): [number, number, number] => {
      // A 1x1 canvas resolves any CSS colour syntax (color-mix, oklab...) to sRGB.
      const ctx = document.createElement('canvas').getContext('2d', { willReadFrequently: true })!;
      ctx.clearRect(0, 0, 1, 1);
      ctx.fillStyle = css;
      ctx.fillRect(0, 0, 1, 1);
      const d = ctx.getImageData(0, 0, 1, 1).data;
      return [d[0], d[1], d[2]];
    };
    const lum = ([r, g, b]: [number, number, number]) => {
      const c = [r, g, b].map((v) => {
        const x = v / 255;
        return x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4;
      });
      return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
    };
    const el = document.querySelector(sel)!;
    const fg = lum(rgb(getComputedStyle(el).color));
    const bg = lum(rgb(getComputedStyle(document.documentElement).getPropertyValue('--bg').trim()));
    const [hi, lo] = fg > bg ? [fg, bg] : [bg, fg];
    return (hi + 0.05) / (lo + 0.05);
  }, selector);
}

test.describe('scroll drives palette and countdown', () => {
  test('top: day palette and 02:00:00', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('#countdown')).toHaveText('02:00:00');
    expect(await bgOf(page)).toBe('#f6f1e7');
  });

  test('bottom: dawn palette and 00:00:00', async ({ page }) => {
    await page.goto('/');
    await scrollToFraction(page, 1);
    await expect(page.locator('#countdown')).toHaveText('00:00:00');
    await expect.poll(() => bgOf(page)).toBe('#fbeee9');
  });

  test('78%: night palette', async ({ page }) => {
    await page.goto('/');
    await scrollToFraction(page, 0.78);
    await expect.poll(() => bgOf(page)).toBe('#22203a');
  });

  test('stays at 00:00:00 after resizing 1280 -> 375 at the bottom', async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto('/');
    await scrollToFraction(page, 1);
    await expect(page.locator('#countdown')).toHaveText('00:00:00');
    await page.setViewportSize({ width: 375, height: 800 });
    await page.evaluate(() => window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'instant' }));
    await expect(page.locator('#countdown')).toHaveText('00:00:00');
    await page.waitForTimeout(500); // let ScrollTrigger refresh settle
    await expect(page.locator('#countdown')).toHaveText('00:00:00');
    expect(await bgOf(page)).toBe('#fbeee9');
  });

  test('keeps text and muted captions at >= 4.5:1 mid-crossover and at the bottom', async ({ page }) => {
    await page.goto('/');
    for (const f of [0, 0.3, 0.4, 0.5, 0.6, 0.78, 0.9, 1]) {
      await scrollToFraction(page, f);
      await page.waitForTimeout(100);
      for (const sel of ['.dream__text p', '.plate-heading__caption', '.herbarium__note']) {
        const ratio = await textContrast(page, sel);
        expect(ratio, `${sel} at ${f}`).toBeGreaterThanOrEqual(4.5);
      }
    }
  });
});

test.describe('reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });

  test('does not start Lenis', async ({ page }) => {
    await page.goto('/');
    await scrollToFraction(page, 0.5);
    await expect(page.locator('html')).not.toHaveClass(/lenis/);
  });

  test('still follows scroll with discrete palettes', async ({ page }) => {
    await page.goto('/');
    await scrollToFraction(page, 0.78);
    await expect.poll(() => bgOf(page)).toBe('#22203a');
    await scrollToFraction(page, 1);
    await expect(page.locator('#countdown')).toHaveText('00:00:00');
  });
});

test('starts Lenis with a fine pointer', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('html')).toHaveClass(/lenis/);
});
