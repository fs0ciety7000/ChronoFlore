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

/**
 * Walks every visible text node in main, the footer and the docked clock and
 * returns those under 4.5:1 against the nearest ancestor with an opaque
 * background (else the page's --bg on <html>).
 */
async function lowContrastText(page: Page): Promise<string[]> {
  return page.evaluate(() => {
    // A 1x1 canvas resolves any CSS colour syntax (color-mix, oklab...) to sRGB.
    const ctx = document.createElement('canvas').getContext('2d', { willReadFrequently: true })!;
    const rgba = (css: string): [number, number, number, number] => {
      ctx.clearRect(0, 0, 1, 1);
      ctx.fillStyle = '#000';
      ctx.fillStyle = css;
      ctx.fillRect(0, 0, 1, 1);
      const d = ctx.getImageData(0, 0, 1, 1).data;
      return [d[0], d[1], d[2], d[3]];
    };
    const lum = ([r, g, b]: number[]) => {
      const c = [r, g, b].map((v) => {
        const x = v / 255;
        return x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4;
      });
      return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
    };
    const ratio = (a: number[], b: number[]) => {
      const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x);
      return (hi + 0.05) / (lo + 0.05);
    };
    const backgroundOf = (el: Element | null): number[] => {
      for (let e = el; e; e = e.parentElement) {
        const bg = getComputedStyle(e).backgroundColor;
        const c = rgba(bg);
        if (bg !== 'transparent' && c[3] === 255) return c;
      }
      return rgba(getComputedStyle(document.documentElement).getPropertyValue('--bg').trim());
    };
    const roots = [...document.querySelectorAll('main, footer, [data-sleep-dock]')];
    const failures: string[] = [];
    for (const root of roots) {
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
      for (let n = walker.nextNode(); n; n = walker.nextNode()) {
        const text = n.textContent!.trim();
        const el = n.parentElement;
        if (!text || !el) continue;
        const style = getComputedStyle(el);
        if (style.visibility !== 'visible') continue;
        const range = document.createRange();
        range.selectNodeContents(n);
        const rect = range.getBoundingClientRect();
        if (rect.width < 2 || rect.height < 2) continue; // display:none, sr-only
        const r = ratio(rgba(style.color), backgroundOf(el));
        if (r < 4.5) failures.push(`${r.toFixed(2)} ${el.tagName.toLowerCase()}.${el.className} "${text.slice(0, 40)}"`);
      }
    }
    return failures;
  });
}

test.describe('scroll drives palette and sleep clock', () => {
  test('top: day palette and 00:00:00', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('#countdown')).toHaveText('00:00:00');
    expect(await bgOf(page)).toBe('#f6f1e7');
  });

  test('bottom: dawn palette and 08:00:00', async ({ page }) => {
    await page.goto('/');
    await scrollToFraction(page, 1);
    await expect(page.locator('#countdown')).toHaveText('08:00:00');
    await expect.poll(() => bgOf(page)).toBe('#fbeee9');
  });

  test('78%: night palette', async ({ page }) => {
    await page.goto('/');
    await scrollToFraction(page, 0.78);
    await expect.poll(() => bgOf(page)).toBe('#22203a');
  });

  test('theme-color follows the palette', async ({ page }) => {
    const themeColor = () => page.locator('meta[name="theme-color"]').getAttribute('content');
    await page.goto('/');
    expect(await themeColor()).toBe('#f6f1e7');
    await scrollToFraction(page, 0.78);
    await expect.poll(themeColor).toBe('#22203a');
    await scrollToFraction(page, 1);
    await expect.poll(themeColor).toBe('#fbeee9');
  });

  test('stays at 08:00:00 after resizing 1280 -> 375 at the bottom', async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto('/');
    await scrollToFraction(page, 1);
    await expect(page.locator('#countdown')).toHaveText('08:00:00');
    await page.setViewportSize({ width: 375, height: 800 });
    await page.evaluate(() => window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'instant' }));
    await expect(page.locator('#countdown')).toHaveText('08:00:00');
    await page.waitForTimeout(500); // let ScrollTrigger refresh settle
    await expect(page.locator('#countdown')).toHaveText('08:00:00');
    expect(await bgOf(page)).toBe('#fbeee9');
  });

  test('keeps every visible text node at >= 4.5:1 on its rendered background', async ({ page }) => {
    test.setTimeout(60_000);
    await page.goto('/');
    for (const f of [0, 0.25, 0.4, 0.5, 0.546, 0.6, 0.68, 0.78, 0.86, 1]) {
      await scrollToFraction(page, f);
      await page.waitForTimeout(100);
      const failures = await lowContrastText(page);
      expect(failures, `text under 4.5:1 at ${f}`).toEqual([]);
    }
  });

  test('keeps herbarium text, open pages included, at >= 4.5:1', async ({ page }) => {
    test.setTimeout(60_000);
    await page.goto('/');
    await page.evaluate(() => document.querySelectorAll('#herbier details').forEach((d) => d.setAttribute('open', '')));
    await expect(page.locator('#herbier details[open] p').first()).toBeVisible();
    for (const f of [0.3, 0.5, 0.6, 0.78, 0.9]) {
      await scrollToFraction(page, f);
      await page.waitForTimeout(100);
      const failures = await lowContrastText(page);
      expect(failures, `text under 4.5:1 with open pages at ${f}`).toEqual([]);
    }
  });
});

/** Contrast of an element's text against the real background colour of `bgSelector`. */
async function contrastOn(page: Page, selector: string, bgSelector: string): Promise<number> {
  return page.evaluate(
    ([sel, bgSel]) => {
      const rgb = (css: string): [number, number, number] => {
        const ctx = document.createElement('canvas').getContext('2d', { willReadFrequently: true })!;
        ctx.clearRect(0, 0, 1, 1);
        ctx.fillStyle = css;
        ctx.fillRect(0, 0, 1, 1);
        const d = ctx.getImageData(0, 0, 1, 1).data;
        return [d[0], d[1], d[2]];
      };
      const lum = (c: [number, number, number]) => {
        const [r, g, b] = c.map((v) => {
          const x = v / 255;
          return x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4;
        });
        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
      };
      const fg = lum(rgb(getComputedStyle(document.querySelector(sel)!).color));
      const bg = lum(rgb(getComputedStyle(document.querySelector(bgSel)!).backgroundColor));
      const [hi, lo] = fg > bg ? [fg, bg] : [bg, fg];
      return (hi + 0.05) / (lo + 0.05);
    },
    [selector, bgSelector],
  );
}

test('keeps .btn--primary and surface-card text at >= 4.5:1 across the crossover', async ({ page }) => {
  await page.goto('/');
  for (const f of [0, 0.4, 0.5, 0.6, 0.78, 1]) {
    await scrollToFraction(page, f);
    await page.waitForTimeout(100);
    const btn = await contrastOn(page, '.btn--primary', '.btn--primary');
    expect(btn, `.btn--primary at ${f}`).toBeGreaterThanOrEqual(4.5);
    const card = await contrastOn(page, '.tool p', '.tool');
    expect(card, `.tool p at ${f}`).toBeGreaterThanOrEqual(4.5);
    const soft = await contrastOn(page, '.btn--soft', '.btn--soft');
    expect(soft, `.btn--soft at ${f}`).toBeGreaterThanOrEqual(4.5);
    const quiet = await contrastOn(page, '.btn--quiet', '.btn--quiet');
    expect(quiet, `.btn--quiet at ${f}`).toBeGreaterThanOrEqual(4.5);
    const note = await contrastOn(page, '.herbarium__note', '.herbarium__note');
    expect(note, `.herbarium__note at ${f}`).toBeGreaterThanOrEqual(4.5);
    const rarity = await contrastOn(page, '.plate__rarity', '.plate__rarity');
    expect(rarity, `.plate__rarity at ${f}`).toBeGreaterThanOrEqual(4.5);
    const hostile = await contrastOn(page, '.plate__hostile', '.plate__hostile');
    expect(hostile, `.plate__hostile at ${f}`).toBeGreaterThanOrEqual(4.5);
    const share = await contrastOn(page, '.share__card p', '.share__card');
    expect(share, `.share__card p at ${f}`).toBeGreaterThanOrEqual(4.5);
  }
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
    await expect(page.locator('#countdown')).toHaveText('08:00:00');
  });
});

test('starts Lenis with a fine pointer', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('html')).toHaveClass(/lenis/);
});

test.describe('docked sleep clock', () => {
  const dock = (page: Page) => page.locator('[data-sleep-dock]');

  /** Rects of the dock and of everything it must never cover at rest. */
  const overlaps = (page: Page) =>
    page.evaluate(() => {
      const d = document.querySelector('[data-sleep-dock]')!.getBoundingClientRect();
      const hit = (r: DOMRect) => r.left < d.right && r.right > d.left && r.top < d.bottom && r.bottom > d.top;
      return [...document.querySelectorAll('#partager .btn, #partager input, footer p')]
        .filter((el) => el.getClientRects().length && hit(el.getBoundingClientRect()))
        .map((el) => el.textContent!.trim() || el.tagName);
    });

  for (const viewport of [
    { width: 1440, height: 900 },
    { width: 390, height: 844 },
  ]) {
    test(`hidden at the top, shown mid-page, 08:00:00 at the bottom (${viewport.width}px)`, async ({ page }) => {
      await page.setViewportSize(viewport);
      await page.goto('/');
      await expect(dock(page)).toHaveAttribute('aria-hidden', 'true');
      await expect(dock(page)).toBeHidden();

      await scrollToFraction(page, 0.5);
      await expect(dock(page)).toBeVisible();
      // Half way, give or take one scrolled pixel: one pixel is 28800 / max seconds
      // of sleep, so the tolerance follows the page height at every viewport.
      const max = await page.evaluate(() => document.documentElement.scrollHeight - innerHeight);
      const tolerance = 28800 / max + 1;
      await expect
        .poll(async () => {
          const m = /(\d+):(\d+):(\d+)/.exec((await dock(page).textContent()) ?? '');
          return m ? Math.abs(+m[1]! * 3600 + +m[2]! * 60 + +m[3]! - 14400) : Infinity;
        })
        .toBeLessThanOrEqual(tolerance);
      const box = (await dock(page).boundingBox())!;
      expect(box.x, 'left side').toBeLessThan(viewport.width / 2);
      expect(box.y + box.height, 'bottom edge').toBeLessThanOrEqual(viewport.height);

      await scrollToFraction(page, 1);
      await expect(dock(page)).toBeVisible();
      await expect(dock(page)).toContainText('08:00:00');
      await page.waitForTimeout(400);
      expect(await overlaps(page), 'covered by the dock at the bottom').toEqual([]);
    });
  }

  test('turns its leaf-hand with the page', async ({ page }) => {
    await page.goto('/');
    await scrollToFraction(page, 0.5);
    await expect(dock(page).locator('[data-logo-hand]')).toHaveCSS('transform', /^matrix\(-1, [^,]+, [^,]+, -1, 0, 0\)$/);
  });

  test('reduced motion: appears without moving', async ({ browser }) => {
    const context = await browser.newContext({ reducedMotion: 'reduce' });
    const page = await context.newPage();
    await page.goto('/');
    await expect(dock(page)).toBeHidden();
    await scrollToFraction(page, 0.5);
    await expect(dock(page)).toBeVisible();
    await expect(dock(page)).toHaveCSS('transform', 'none');
    await context.close();
  });
});
