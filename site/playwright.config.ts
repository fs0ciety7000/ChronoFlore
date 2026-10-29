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
  webServer: {
    command: 'npm run build && npx astro preview --port 4321',
    url: 'http://localhost:4321',
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
