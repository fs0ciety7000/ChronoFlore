import { expect, test } from '@playwright/test';

// Port 4321: built with an empty manifest. Port 4322: built with
// tests/e2e/fixtures/downloads.json (see playwright.config.ts).
const FIXTURE = 'http://localhost:4322/';
const WINDOWS_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';

test('without builds, the hero says "bientôt" and links to nothing under /telecharger/', async ({ page }) => {
  await page.goto('/');
  const row = page.locator('.hero [data-downloads]');
  await expect(row).toHaveAttribute('data-downloads', 'soon');
  await expect(row).toContainText('bientôt disponibles');
  await expect(page.locator('a[href^="/telecharger/"]')).toHaveCount(0);
});

test.describe('with builds', () => {
  test.use({ userAgent: WINDOWS_UA });

  test('renders one button per platform with its size, and the notes', async ({ page }) => {
    await page.goto(FIXTURE);
    const row = page.locator('.hero [data-downloads="ready"]');
    await expect(row).toContainText('version 0.1.42');
    const buttons = row.locator('a.btn');
    await expect(buttons).toHaveCount(3);
    await expect(buttons.nth(0)).toHaveAttribute('href', '/telecharger/ChronoFlore-macos.dmg');
    await expect(buttons.nth(0)).toContainText(/macOS\s*\.dmg · 65\sMo/);
    await expect(buttons.nth(1)).toHaveAttribute('href', '/telecharger/ChronoFlore-windows.exe');
    await expect(buttons.nth(1)).toContainText(/Windows\s*\.exe · 111\sMo/);
    await expect(buttons.nth(2)).toHaveAttribute('href', '/telecharger/ChronoFlore-linux.deb');
    await expect(row.locator('a[href="/telecharger/ChronoFlore-linux.tar.gz"]')).toContainText('.tar.gz');
    await expect(row).toContainText('clic droit');
    await expect(row).toContainText('Exécuter quand même');
    for (const link of await row.locator('a').all()) {
      expect((await link.boundingBox())!.height).toBeGreaterThanOrEqual(44);
    }
  });

  test("highlights the visitor's OS", async ({ page }) => {
    await page.goto(FIXTURE);
    await expect(page.locator('[data-downloads] li[data-current]')).toHaveAttribute('data-os', 'windows');
  });

  test('wraps without horizontal scroll at 360 px', async ({ page }) => {
    await page.setViewportSize({ width: 360, height: 740 });
    await page.goto(FIXTURE);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(360);
    const box = (await page.locator('[data-downloads]').boundingBox())!;
    expect(box.x + box.width).toBeLessThanOrEqual(360);
  });
});
