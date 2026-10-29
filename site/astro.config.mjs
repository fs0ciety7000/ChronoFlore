import { existsSync, readFileSync } from 'node:fs';
import { defineConfig } from 'astro/config';
import { modelIds } from './src/scripts/diorama/island.ts';

/** Fails the build when a Polyfork model of the diorama was not fetched. */
function requireModels() {
  return {
    name: 'chronoflore:require-models',
    hooks: {
      'astro:build:start': () => {
        const dir = new URL('./public/models/polyfork/', import.meta.url);
        const manifestUrl = new URL('manifest.json', dir);
        const hint = 'run `npm run fetch:models` first';
        if (!existsSync(manifestUrl)) throw new Error(`Polyfork models missing: ${hint}.`);
        const manifest = JSON.parse(readFileSync(manifestUrl, 'utf8'));
        const missing = modelIds().filter((id) => !manifest[id] || !existsSync(new URL(manifest[id], dir)));
        if (missing.length) throw new Error(`Polyfork models missing (${missing.join(', ')}): ${hint}.`);
      },
    },
  };
}

export default defineConfig({
  site: 'https://chronoflore.cardormedia.com',
  integrations: [requireModels()],
  // three.js is one deferred chunk (~660 kB min, ~170 kB gzip), loaded after idle.
  vite: { build: { chunkSizeWarningLimit: 700 } },
});
