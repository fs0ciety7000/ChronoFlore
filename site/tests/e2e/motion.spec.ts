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

  test('leaving the window or losing focus hides the net and gives the cursor back', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('load');
    const cursor = page.locator('.cursor-net');
    const html = page.locator('html');
    await page.mouse.move(400, 300);
    await expect(cursor).toHaveClass(/is-visible/);
    await expect(html).toHaveClass(/has-cursor-net/);
    await page.evaluate(() => document.body.dispatchEvent(new PointerEvent('pointerout', { bubbles: true, relatedTarget: null })));
    await expect(cursor).not.toHaveClass(/is-visible/);
    await expect(html).not.toHaveClass(/has-cursor-net/);
    // Back in, press, then the window blurs mid-press (alt-tab).
    await page.mouse.move(420, 320);
    await page.mouse.down();
    await expect(cursor).toHaveClass(/is-pressed/);
    await page.evaluate(() => window.dispatchEvent(new Event('blur')));
    await expect(cursor).not.toHaveClass(/is-visible/);
    await expect(cursor).not.toHaveClass(/is-pressed/);
    await expect(html).not.toHaveClass(/has-cursor-net/);
    await page.mouse.up();
  });

  test('system cursor comes back over text fields only, as cursor.ts decides', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('load');
    await page.mouse.move(400, 300);
    await expect(page.locator('html')).toHaveClass(/has-cursor-net/);
    const cursors = await page.evaluate(() => {
      const make = (html: string) => {
        const host = document.createElement('div');
        host.innerHTML = html;
        document.body.append(host);
        return getComputedStyle(host.firstElementChild!).cursor;
      };
      return {
        text: make('<input type="text">'),
        editable: make('<div contenteditable="true">x</div>'),
        checkbox: make('<input type="checkbox">'),
        submit: make('<input type="submit">'),
      };
    });
    expect(cursors.text).not.toBe('none');
    expect(cursors.editable).not.toBe('none');
    expect(cursors.checkbox).toBe('none');
    expect(cursors.submit).toBe('none');
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
    await expect(card).toHaveCSS('opacity', '1', { timeout: 10_000 });
    await expect(card).toHaveCSS('transform', /none|matrix\(1, 0, 0, 1, 0, 0\)/);
    // Once only: scrolling away keeps it revealed.
    await scrollToFraction(page, 0);
    await page.waitForTimeout(200);
    await expect(card).toHaveClass(/is-revealed/);
    await expect(card).toHaveCSS('opacity', '1');
  });

  test('the reveal transition is dropped once played, leaving component transitions alone', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('load');
    const card = page.locator('.tool').first();
    await card.scrollIntoViewIfNeeded();
    await expect(card).toHaveCSS('opacity', '1', { timeout: 10_000 });
    await expect(card).not.toHaveClass(/is-revealing/, { timeout: 10_000 });
    // .tool declares no transition of its own: nothing must be left behind.
    await expect(card).toHaveCSS('transition-duration', '0s');
    await expect(card).toHaveCSS('transition-delay', '0s');
  });

  test('each element is observed once and unobserved once revealed', async ({ page }) => {
    await page.addInitScript(() => {
      const w = window as unknown as { __io: { observed: number; unobserved: Set<Element> } };
      w.__io = { observed: 0, unobserved: new Set() };
      const proto = IntersectionObserver.prototype;
      const observe = proto.observe;
      const unobserve = proto.unobserve;
      proto.observe = function (el) {
        w.__io.observed++;
        return observe.call(this, el);
      };
      proto.unobserve = function (el) {
        w.__io.unobserved.add(el);
        return unobserve.call(this, el);
      };
    });
    await page.goto('/');
    await page.waitForLoadState('load');
    const pending = await page.$$eval('[data-reveal]:not(.is-revealed)', (els) => els.length);
    expect(pending).toBeGreaterThan(0);
    // Walk down the page so every pending element crosses the viewport.
    for (let f = 0.1; f <= 1.0001; f += 0.1) {
      await scrollToFraction(page, f);
      await page.waitForTimeout(120);
    }
    await expect(page.locator('[data-reveal]:not(.is-revealed)')).toHaveCount(0);
    const counts = await page.evaluate(() => {
      const w = window as unknown as { __io: { observed: number; unobserved: Set<Element> } };
      const revealTargets = [...w.__io.unobserved].filter((el) => el.matches('[data-reveal]'));
      return { unobserved: revealTargets.length };
    });
    expect(counts.unobserved).toBe(pending);
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
    await expect(card).not.toHaveClass(/is-gesturing/, { timeout: 10_000 });
  });
});
