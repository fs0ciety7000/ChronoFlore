import { expect, test, type Page } from '@playwright/test';

async function scrollToFraction(page: Page, f: number) {
  await page.evaluate((frac) => {
    const max = document.documentElement.scrollHeight - innerHeight;
    scrollTo({ top: max * frac, behavior: 'instant' });
  }, f);
}

/** Rotation (degrees, -180..180] of an element's computed transform matrix. */
const handAngle = (page: Page) =>
  page.evaluate(() => {
    const t = getComputedStyle(document.querySelector('[data-animated-hand] [data-logo-hand]')!).transform;
    const m = new DOMMatrix(t === 'none' ? undefined : t);
    return (Math.atan2(m.b, m.a) * 180) / Math.PI;
  });

test.describe('custom net cursor', () => {
  test('follows a fine pointer and stays out of the accessibility tree', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('load');
    await page.mouse.move(400, 300);
    const cursor = page.locator('.cursor-net');
    await expect(cursor).toHaveCount(1);
    await expect(cursor).toHaveAttribute('aria-hidden', 'true');
    expect(await cursor.evaluate((el) => getComputedStyle(el).pointerEvents)).toBe('none');
    // The hotspot (hoop centre) sits on the pointer, 1:1, no lag.
    const hotspot = () =>
      cursor.evaluate((el) => {
        const r = el.querySelector('[data-hotspot]')!.getBoundingClientRect();
        return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
      });
    await expect.poll(async () => Math.hypot((await hotspot()).x - 400, (await hotspot()).y - 300)).toBeLessThan(2);
    await page.mouse.move(700, 520);
    await expect.poll(async () => Math.hypot((await hotspot()).x - 700, (await hotspot()).y - 520)).toBeLessThan(2);
    expect(await cursor.evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
  });

  test('marks links and buttons under the pointer', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('load');
    const box = (await page.locator('.hero .btn--primary').boundingBox())!;
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await expect(page.locator('.cursor-net')).toHaveClass(/is-over-action/);
    await page.mouse.move(box.x + box.width / 2, box.y - 120);
    await expect(page.locator('.cursor-net')).not.toHaveClass(/is-over-action/);
  });

  test('does not exist on touch screens', async ({ browser }) => {
    const context = await browser.newContext({ hasTouch: true, isMobile: true, viewport: { width: 390, height: 844 } });
    const page = await context.newPage();
    await page.goto('/');
    await page.waitForLoadState('load');
    await expect(page.locator('.cursor-net')).toHaveCount(0);
    await context.close();
  });

  test('does not exist with reduced motion', async ({ browser }) => {
    const context = await browser.newContext({ reducedMotion: 'reduce' });
    const page = await context.newPage();
    await page.goto('/');
    await page.mouse.move(400, 300);
    await page.waitForLoadState('load');
    await expect(page.locator('.cursor-net')).toHaveCount(0);
    await context.close();
  });
});

test.describe('scroll reveals', () => {
  test('reduced motion: every [data-reveal] is visible without scrolling', async ({ browser }) => {
    const context = await browser.newContext({ reducedMotion: 'reduce' });
    const page = await context.newPage();
    await page.goto('/');
    await page.waitForLoadState('load');
    const opacities = await page.$$eval('[data-reveal]', (els) => els.map((el) => getComputedStyle(el).opacity));
    expect(opacities.length).toBeGreaterThanOrEqual(10);
    expect(new Set(opacities)).toEqual(new Set(['1']));
    await context.close();
  });

  test('without JavaScript, every [data-reveal] is visible', async ({ browser }) => {
    const context = await browser.newContext({ javaScriptEnabled: false });
    const page = await context.newPage();
    await page.goto('/');
    const opacities = await page.$$eval('[data-reveal]', (els) => els.map((el) => getComputedStyle(el).opacity));
    expect(opacities.length).toBeGreaterThanOrEqual(10);
    expect(new Set(opacities)).toEqual(new Set(['1']));
    await context.close();
  });

  test('below-the-fold cards wait, then rise in once when scrolled into view', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('load');
    const card = page.locator('.tool').first();
    await expect(card).toHaveCSS('opacity', '0');
    await card.scrollIntoViewIfNeeded();
    await expect(card).toHaveClass(/is-revealed/);
    await expect(card).toHaveCSS('opacity', '1', { timeout: 3000 });
    await expect(card).toHaveCSS('transform', /none|matrix\(1, 0, 0, 1, 0, 0\)/);
    // Once only: scrolling away keeps it revealed.
    await scrollToFraction(page, 0);
    await page.waitForTimeout(200);
    await expect(card).toHaveClass(/is-revealed/);
    await expect(card).toHaveCSS('opacity', '1');
  });

  test('copy already in view on load is never hidden', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('load');
    const inView = await page.$$eval('[data-reveal]', (els) =>
      els
        .filter((el) => el.getBoundingClientRect().top < innerHeight)
        .map((el) => [el.classList.contains('is-revealed'), getComputedStyle(el).opacity]),
    );
    for (const [revealed, opacity] of inView) {
      expect(revealed).toBe(true);
      expect(opacity).toBe('1');
    }
  });
});

test.describe('sleep clock leaf-hand', () => {
  test('turns with progress: 0 deg at the top, 180 deg at 50 %', async ({ page }) => {
    await page.goto('/');
    await expect.poll(() => handAngle(page)).toBeCloseTo(0, 0);
    await scrollToFraction(page, 0.5);
    await expect.poll(async () => Math.abs(await handAngle(page))).toBeCloseTo(180, 0);
  });
});

test.describe('tool gestures', () => {
  test('hovering a tool card plays its gesture once', async ({ page }) => {
    await page.goto('/');
    const card = page.locator('.tool[data-tool="harpon"]');
    await card.scrollIntoViewIfNeeded();
    await card.hover();
    await expect(card).toHaveClass(/is-gesturing/);
    await expect(card).not.toHaveClass(/is-gesturing/, { timeout: 3000 });
  });
});
