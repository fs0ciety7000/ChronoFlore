import { existsSync } from 'node:fs';
import { chromium, defineConfig, devices } from '@playwright/test';

// Use Playwright's own Chromium when it is installed; otherwise fall back to a
// preinstalled one (CHROMIUM_PATH, then the sandbox's /opt/pw-browsers build).
const fallback = process.env.CHROMIUM_PATH ?? '/opt/pw-browsers/chromium';
const executablePath = existsSync(chromium.executablePath())
  ? undefined
  : existsSync(fallback)
    ? fallback
    : undefined;

export default defineConfig({
  testDir: 'tests/e2e',
  fullyParallel: true,
  reporter: 'list',
  use: {
    baseURL: 'http://localhost:4321',
    ...devices['Desktop Chrome'],
    launchOptions: { executablePath },
  },
  webServer: [
    {
      // Desktop downloads not fetched: the "bientôt disponible" state.
      command: 'npm run build && npx astro preview --port 4321',
      url: 'http://localhost:4321',
      env: { DOWNLOADS_MANIFEST: 'tests/e2e/fixtures/downloads-empty.json' },
      reuseExistingServer: !process.env.CI,
      timeout: 120_000,
    },
    {
      // Same site built with a fixture manifest (tests/e2e/downloads.spec.ts).
      // Started after the first one (Playwright sets servers up in order).
      command:
        'npx astro build --outDir .e2e-downloads && npx vite preview --outDir .e2e-downloads --port 4322 --strictPort',
      url: 'http://localhost:4322',
      env: { DOWNLOADS_MANIFEST: 'tests/e2e/fixtures/downloads.json' },
      reuseExistingServer: !process.env.CI,
      timeout: 120_000,
    },
  ],
});
