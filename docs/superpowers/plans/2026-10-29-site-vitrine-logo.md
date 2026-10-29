# Site vitrine et logo ChronoFlore — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Livrer sur `https://chronoflore.cardormedia.com` une page unique où le scroll fait passer un diorama 3D Polyfork et toute la page du jour à la nuit puis à l'aube, avec le logo « Fleur-horloge » décliné pour le site et le jeu.

**Architecture:** Astro 5 statique. La logique de récit est pure et testée (`progress ∈ [0,1]` → facteurs nuit/aube, palette, compte à rebours, lumière). Une couche « scroll » mesure la progression et la diffuse : variables CSS pour la page, `setProgress()` pour la scène three.js. La 3D est un îlot chargé après le premier affichage ; sans elle, un poster et la palette CSS racontent la même histoire.

**Tech Stack:** Astro 5, TypeScript, three.js, GSAP + ScrollTrigger, Lenis, Vitest, Playwright, @fontsource (Fredoka, Nunito, Fraunces), png-to-ico. Node 22.

**Spec:** `docs/superpowers/specs/2026-10-29-site-vitrine-logo-design.md` (textes et logo : `docs/superpowers/specs/mockups/`).

## Global Constraints

- Langue : français uniquement ; `<html lang="fr">`.
- Textes : copiés tels quels des maquettes `SiteJour.dc.html` (structure, accroche, sections) et `SiteNuit.dc.html` (noms latins, légendes « Planche I… IV » en Fraunces italique). Titre d'ouverture exact : « Deux heures de sommeil. Toute une flore à capturer. »
- Spécimens : Nostalgie rampante / *Nostalgia repens*, Joie-pissenlit / *Gaudium volans*, Doute grimpant / *Dubium scandens*, Souvenir d'été / *Memoria aestiva* ; mention « [Espèces d'exemple — à définir avec le game design] ».
- Emplacement héroïne : texte exact « [Rendu 3D de l'héroïne — à venir] ».
- Palette jour : fond `#f6f1e7`, encre `#3b3350`, rose `#f4b9c8`, lavande `#cdc4ef`, menthe `#8fcf9f`, surface `#fffdf8`. Nuit : fond `#22203a`, texte `#ede8fb`, rose `#f7c3d2`, surface `#2d2a4c`. Aube : fond `#fbeee9`, encre `#3b3350`, rose `#f4b9c8`, surface `#fffdf8`.
- Contrastes texte/fond ≥ 4.5:1 à toute valeur de progression.
- Assets 3D : Polyfork (`https://polyfork.dev/cdn/{id}.glb`, sans clé) ou faits maison. Jamais d'ACES à l'exposition 1 sur les modèles Polyfork : `renderer.toneMapping = THREE.NoToneMapping`. Pas de rescale pour faire coller une taille.
- Les GLB Polyfork ne sont **pas** commités : téléchargés au build (`npm run fetch:models`) dans `site/public/models/polyfork/` (ignoré par git). Le build échoue si un GLB manque.
- Polices autohébergées via @fontsource, aucun appel Google Fonts en production.
- Budget : GLB cumulés ≤ 4 Mo ; poster ≤ 200 Ko (WebP) ; JS initial (hors 3D différée) ≤ 80 Ko gzip.
- `prefers-reduced-motion: reduce` : ni Lenis, ni caméra animée, ni canvas 3D ; poster fixe ; palette en fondu simple.
- Canvas 3D `aria-hidden="true"` ; tout le texte est dans le DOM.
- Déploiement : Coolify, base `site/`, `site/Dockerfile`, branche `claude/focused-cerf-d2kgbx`. DNS Cloudflare `A chronoflore.cardormedia.com` → `COOLIFY_SERVER_IP`, DNS only. Ne rien toucher d'autre dans Coolify ni dans la zone.
- Secrets : lus depuis l'environnement (`COOLIFY_API_URL`, `COOLIFY_API_TOKEN`, `COOLIFY_SERVER_IP`, `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`), jamais écrits dans le dépôt ni affichés dans les logs.

## Review Focus

1. **WebGL absent ou contexte perdu** → le poster reste, aucune erreur console, le scroll et la palette continuent. Test : Task 7, e2e avec WebGL désactivé.
2. **Écran de 360 px de large** → aucun défilement horizontal, la navigation passe à la ligne. Test : Task 3, e2e viewport 360×740.
3. **Presse-papiers indisponible ou partage natif annulé** → « Copier le lien » affiche le lien sélectionnable au lieu d'échouer ; une annulation de `navigator.share` (AbortError) n'est pas une erreur. Test : Task 5, unitaires sur `sharePage`.
4. **Redimensionnement / rotation / scroll très rapide** → la progression reste bornée à [0,1], compte à rebours et palette cohérents avec la position. Test : Task 1 (bornes), Task 4 (e2e resize).
5. **Polyfork indisponible au build** → le build Docker échoue avec un message clair au lieu de livrer une île vide. Test : Task 7, unitaire sur le script de fetch.

---

## Structure des fichiers

```
site/
  package.json, astro.config.mjs, tsconfig.json, vitest.config.ts, playwright.config.ts
  Dockerfile, nginx.conf
  scripts/
    fetch-models.mjs        # télécharge les GLB listés dans src/scripts/diorama/island.ts
    export-brand.mjs        # rasterise le logo (PNG, ICO, OG) avec Playwright
    render-poster.mjs       # capture poster.webp et og.png depuis la page buildée
  src/
    layouts/Base.astro      # <head>, meta, OG, favicons, polices
    pages/index.astro       # assemble les sections
    components/
      Logo.astro            # symbole SVG inline (+ logotype optionnel)
      Header.astro, Hero.astro, Countdown.astro, Dream.astro, Hunter.astro,
      Tools.astro, Herbarium.astro, Share.astro, Footer.astro
    styles/tokens.css       # jetons jour/nuit/aube + variables pilotées
    styles/global.css
    scripts/
      color.ts              # mixHex
      timeline.ts           # progression → facteurs, palette, compte à rebours
      lighting.ts           # facteurs → réglages de lumière de la scène
      env.ts                # détection reduced-motion, pointeur fin, WebGL, capacité
      share.ts              # liens de partage, sharePage()
      scroll.ts             # Lenis + ScrollTrigger → CSS vars + écouteurs
      reveal.ts, cursor.ts  # micro-interactions
      diorama/
        island.ts           # composition : liste des placements Polyfork
        scene.ts            # createDiorama()
        loader.ts           # chargement différé + fondu poster → canvas
  public/
    models/polyfork/        # (gitignored) GLB téléchargés
    poster.webp, og.png, favicon.svg, favicon.ico, apple-touch-icon.png
  tests/unit/*.test.ts, tests/e2e/*.spec.ts
branding/
  chronoflore-symbol.svg, chronoflore-logo-horizontal.svg, chronoflore-logo-stacked.svg,
  chronoflore-symbol-mono-ink.svg, chronoflore-symbol-mono-cream.svg, png/…
game/icon.svg
```

---

### Task 1: Outillage et logique de récit pure

**Files:**
- Modify: `site/package.json`, `site/tsconfig.json`
- Create: `site/vitest.config.ts`, `site/src/scripts/color.ts`, `site/src/scripts/timeline.ts`
- Test: `site/tests/unit/color.test.ts`, `site/tests/unit/timeline.test.ts`

**Interfaces:**
- Produces:
  - `mixHex(a: string, b: string, t: number): string` — `#rrggbb`, `t` borné à [0,1].
  - `type Palette = { bg: string; ink: string; accent: string; surface: string }`
  - `PALETTES: { day: Palette; night: Palette; dawn: Palette }` (valeurs des Global Constraints ; `ink` nuit = `#ede8fb`).
  - `clampProgress(p: number): number` — NaN → 0, borné [0,1].
  - `nightFactor(p): number` = smoothstep(0.08, 0.75, p) ; `dawnFactor(p): number` = smoothstep(0.82, 0.97, p).
  - `paletteAt(p): Palette` — mix(day, night, nightFactor) puis mix(résultat, dawn, dawnFactor).
  - `countdownAt(p): string` — `HH:MM:SS` de `round(7200 × (1 − p))` secondes.

- [ ] **Step 1: Ajouter les dépendances** — `astro`, `three`, `gsap`, `lenis`, `@fontsource/fredoka`, `@fontsource/nunito`, `@fontsource/fraunces` ; dev : `vitest`, `@playwright/test`, `@types/three`, `png-to-ico`, `@astrojs/check`, `typescript`. Scripts : `test` (`vitest run`), `test:e2e` (`playwright test`), `fetch:models`, `brand`, `poster`. `npm install` génère `package-lock.json` (commité).
- [ ] **Step 2: Écrire les tests qui échouent**

```ts
// color.test.ts
expect(mixHex('#000000', '#ffffff', 0.5)).toBe('#808080');
expect(mixHex('#f6f1e7', '#22203a', 0)).toBe('#f6f1e7');
expect(mixHex('#f6f1e7', '#22203a', 2)).toBe('#22203a');
// timeline.test.ts
expect(countdownAt(0)).toBe('02:00:00');
expect(countdownAt(1)).toBe('00:00:00');
expect(countdownAt(0.5)).toBe('01:00:00');
expect(countdownAt(-3)).toBe('02:00:00');
expect(countdownAt(NaN)).toBe('02:00:00');
expect(paletteAt(0)).toEqual(PALETTES.day);
expect(paletteAt(0.78).bg).toBe(PALETTES.night.bg);
expect(paletteAt(1)).toEqual(PALETTES.dawn);
expect(nightFactor(0.08)).toBe(0); expect(nightFactor(0.75)).toBe(1);
// contraste : pour p de 0 à 1 par pas de 0.01, contrast(paletteAt(p).ink, paletteAt(p).bg) >= 4.5
```

- [ ] **Step 3: Lancer** `cd site && npx vitest run` → FAIL (modules absents).
- [ ] **Step 4: Implémenter `color.ts` et `timeline.ts`.** Contraste : luminance relative WCAG (helper local au test). Si le contraste échoue autour du milieu de la transition, l'encre bascule de `PALETTES.day.ink` à `PALETTES.night.ink` au point de contraste égal plutôt que d'être interpolée (règle à garder dans `paletteAt`).
- [ ] **Step 5: Lancer** `npx vitest run` → PASS ; `npx astro check` → 0 erreur.
- [ ] **Step 6: Commit** `feat(site): add narrative timeline, palette and countdown logic`.

---

### Task 2: Logo « Fleur-horloge » et déclinaisons

**Files:**
- Create: `branding/chronoflore-symbol.svg`, `branding/chronoflore-logo-horizontal.svg`, `branding/chronoflore-logo-stacked.svg`, `branding/chronoflore-symbol-mono-ink.svg`, `branding/chronoflore-symbol-mono-cream.svg`, `site/scripts/export-brand.mjs`, `site/src/components/Logo.astro`, `game/icon.svg`
- Generated (commités) : `branding/png/chronoflore-symbol-{512,1024}.png`, `site/public/favicon.svg`, `site/public/favicon.ico`, `site/public/apple-touch-icon.png`
- Modify: `game/project.godot` (`config/icon="res://icon.svg"`)
- Test: `site/tests/unit/brand.test.ts`

**Interfaces:**
- Produces: `<Logo variant="symbol" | "horizontal" size={number} animatedHand?: boolean />` ; l'aiguille-feuille porte `data-logo-hand` (pivot au centre du cadran) pour Task 8.

- [ ] **Step 1: Test qui échoue** — `brand.test.ts` : chaque SVG de `branding/` est un XML valide avec `viewBox`, ne contient ni `<text>` ni `<image>` (logotype vectorisé), et le symbole contient les couleurs `#f4b9c8`, `#cdc4ef`, `#8fcf9f`, `#3b3350`.
- [ ] **Step 2: Lancer** `npx vitest run tests/unit/brand.test.ts` → FAIL.
- [ ] **Step 3: Dessiner les SVG** depuis la géométrie exacte de la piste A (`docs/superpowers/specs/mockups/Main.dc.html`). Logotype : « Chrono » `#3b3350` + « Flore » `#e48aa3`, Fredoka 600, converti en chemins (rendu Playwright de la police @fontsource puis extraction des contours, ou `opentype.js` en dev dep). Monochromes : tout en `#3b3350` / tout en `#fff6e8`. Lisibilité à 16 px : la version favicon garde seulement pétales + cadran + aiguille-feuille (sans aiguille fine).
- [ ] **Step 4: `export-brand.mjs`** rasterise avec Playwright (`chromium.launch()`) les PNG 512/1024, `apple-touch-icon.png` 180, et produit `favicon.ico` (16/32/48) via `png-to-ico`. `game/icon.svg` = copie du symbole.
- [ ] **Step 5: Lancer** `npm run brand && npx vitest run tests/unit/brand.test.ts` → PASS ; vérifier visuellement `branding/png/chronoflore-symbol-512.png` et le favicon à 16 px.
- [ ] **Step 6: Lancer** `godot --headless --path game --import` puis le test runner Godot → `Results: 1 passed, 0 failed`.
- [ ] **Step 7: Commit** `feat(brand): add Fleur-horloge logo, favicons and game icon`.

---

### Task 3: Page statique complète

**Files:**
- Create: `site/src/layouts/Base.astro`, `site/src/styles/tokens.css`, `site/src/styles/global.css`, les composants de section, `site/playwright.config.ts`
- Modify: `site/src/pages/index.astro`
- Test: `site/tests/e2e/page.spec.ts`

**Interfaces:**
- Consumes: `PALETTES` (Task 1), `<Logo>` (Task 2).
- Produces:
  - Variables CSS sur `:root` : `--bg`, `--ink`, `--accent`, `--surface`, `--progress` (0 par défaut) ; valeurs initiales = jour.
  - Ancres : `#top`, `#reve`, `#chasseuse`, `#outils`, `#herbier`, `#partager` ; `<section data-scene>` sur chaque section.
  - Conteneur `<div id="diorama" data-state="poster">` contenant `<img src="/poster.webp" alt="">` (poster temporaire : capture de la maquette tant que Task 9 n'a pas tourné).
  - `<output id="countdown">02:00:00</output>`.

- [ ] **Step 1: Test e2e qui échoue** — `playwright.config.ts` : `webServer` = `npm run build && npx astro preview --port 4321`, `use.launchOptions.executablePath = '/opt/pw-browsers/chromium'` si la version de `@playwright/test` ne trouve pas son navigateur. Assertions :
  - `h1` a pour texte « Deux heures de sommeil. Toute une flore à capturer. »
  - les six ancres existent ; 4 cartes de spécimens ; l'emplacement héroïne a le texte exact des Global Constraints ;
  - à 360×740 : `document.documentElement.scrollWidth <= 360` ;
  - aucune requête vers `fonts.googleapis.com` ; aucune erreur console ;
  - navigation au clavier : Tab atteint le lien « Le rêve » puis le bouton « Partager le rêve ».
- [ ] **Step 2: Lancer** `npx playwright test tests/e2e/page.spec.ts` → FAIL.
- [ ] **Step 3: Implémenter** layout, jetons et sections en reprenant les maquettes (mise en page de `SiteJour`, légendes « Planche » et noms latins de `SiteNuit`). Les couleurs passent toutes par les variables CSS. Pas de dégradés génériques, pas de cartes à bordure gauche, pas d'emoji.
- [ ] **Step 4: Lancer** les e2e → PASS ; `npx astro check` → 0 erreur.
- [ ] **Step 5: Commit** `feat(site): build static one-page layout from approved mockups`.

---

### Task 4: Scroll → palette et compte à rebours

**Files:**
- Create: `site/src/scripts/env.ts`, `site/src/scripts/scroll.ts`
- Modify: `site/src/pages/index.astro` (script client)
- Test: `site/tests/unit/env.test.ts`, `site/tests/e2e/scroll.spec.ts`

**Interfaces:**
- Consumes: `clampProgress`, `paletteAt`, `countdownAt`, `nightFactor`, `dawnFactor` (Task 1).
- Produces:
  - `type Env = { reducedMotion: boolean; finePointer: boolean; webgl: boolean; saveData: boolean; deviceMemory?: number }`, `readEnv(): Env`.
  - `shouldUse3D(env: Env): boolean` — faux si `reducedMotion`, `!webgl`, `saveData` ou `deviceMemory < 4`.
  - `initScroll(env: Env): { onProgress(cb: (p: number) => void): () => void; destroy(): void }` — écrit `--bg/--ink/--accent/--surface/--progress` sur `:root` et le texte de `#countdown` à chaque frame de scroll ; Lenis seulement si `finePointer && !reducedMotion`.

- [ ] **Step 1: Tests qui échouent** — `env.test.ts` : `shouldUse3D` faux pour chacun des quatre motifs, vrai pour `{reducedMotion:false, finePointer:true, webgl:true, saveData:false, deviceMemory:8}`. `scroll.spec.ts` : en haut, `#countdown` = `02:00:00` et `--bg` = `#f6f1e7` ; tout en bas = `00:00:00` et `--bg` = `#fbeee9` ; à 78 % = `#22203a` ; après redimensionnement 1280→375 en bas de page, toujours `00:00:00` ; avec `reducedMotion: 'reduce'` (contexte Playwright), aucune classe `lenis` sur `<html>`.
- [ ] **Step 2: Lancer** → FAIL.
- [ ] **Step 3: Implémenter.** La progression = `scrollY / (scrollHeight − innerHeight)`, recalculée par ScrollTrigger (`refresh` au resize). Les transitions CSS de couleur ne sont actives qu'en reduced-motion (fondu de 600 ms entre états discrets jour/nuit/aube).
- [ ] **Step 4: Lancer** unitaires + e2e → PASS.
- [ ] **Step 5: Commit** `feat(site): drive palette and countdown from scroll`.

---

### Task 5: Partage et métadonnées

**Files:**
- Create: `site/src/scripts/share.ts`
- Modify: `site/src/components/Share.astro`, `site/src/layouts/Base.astro`
- Test: `site/tests/unit/share.test.ts`, ajout dans `site/tests/e2e/page.spec.ts`

**Interfaces:**
- Produces:
  - `SHARE_URL = 'https://chronoflore.cardormedia.com/'`, `SHARE_TEXT = 'ChronoFlore — deux heures de sommeil, toute une flore à capturer.'`
  - `shareLinks(url, text): { bluesky: string; x: string; facebook: string }` — `https://bsky.app/intent/compose?text=`, `https://x.com/intent/post?text=&url=`, `https://www.facebook.com/sharer/sharer.php?u=` (paramètres encodés).
  - `sharePage(nav: Pick<Navigator,'share'|'clipboard'>, url, text): Promise<'shared'|'copied'|'manual'|'cancelled'>`.

- [ ] **Step 1: Tests qui échouent** — liens encodés (un `&` dans le texte devient `%26`) ; `sharePage` : `share` présent → `'shared'` ; `share` rejette `AbortError` → `'cancelled'` ; pas de `share`, clipboard OK → `'copied'` ; clipboard absent ou rejeté → `'manual'`. e2e : meta `og:title`, `og:description`, `og:image` = `https://chronoflore.cardormedia.com/og.png`, `twitter:card` = `summary_large_image`, `<link rel="icon">` SVG et ICO.
- [ ] **Step 2: Lancer** → FAIL.
- [ ] **Step 3: Implémenter.** UI : « Copier le lien » → libellé « Lien copié » 2 s, sans modale ; `'manual'` → affiche un `<input readonly>` présélectionné avec l'URL. Sur mobile (`navigator.share`), le bouton principal « Partager le rêve » appelle `sharePage`.
- [ ] **Step 4: Lancer** → PASS.
- [ ] **Step 5: Commit** `feat(site): add share actions and Open Graph metadata`.

---

### Task 6: Premier déploiement (Coolify + DNS) — point de contrôle utilisateur

**Files:**
- Create: `site/scripts/deploy/README.md` (procédure rejouable, sans secret)
- Modify: `site/Dockerfile` (`npm ci`, puis `npm run fetch:models` à partir de Task 7, `npm run build`), `site/nginx.conf` (cache long sur `/_astro/*` et `/models/*`, `no-cache` sur `index.html`)

- [ ] **Step 1: Coolify** (`$COOLIFY_API_URL/api/v1`, `Authorization: Bearer $COOLIFY_API_TOKEN`) : lister serveurs et projets ; si le dépôt n'est pas accessible publiquement, lister les sources GitHub App de Coolify et l'utiliser. Créer **une** application : build pack Dockerfile, base directory `/site`, branche `claude/focused-cerf-d2kgbx`, domaine `https://chronoflore.cardormedia.com`, port 80. Si une application avec ce domaine existe déjà, la réutiliser au lieu d'en créer une.
- [ ] **Step 2: Cloudflare** : trouver la zone `cardormedia.com` (`GET /client/v4/zones?name=cardormedia.com`), créer ou mettre à jour l'enregistrement `A chronoflore` → `$COOLIFY_SERVER_IP`, `proxied: false`, TTL auto.
- [ ] **Step 3: Déclencher le déploiement** et suivre jusqu'à `finished` ; en cas d'échec, lire les logs de build.
- [ ] **Step 4: Vérifier** `curl -sI https://chronoflore.cardormedia.com/` → `HTTP/2 200`, certificat valide (`curl` sans `-k`), `h1` présent dans le HTML.
- [ ] **Step 5: Commit** `chore(deploy): document Coolify and Cloudflare setup`.
- [ ] **Step 6: POINT DE CONTRÔLE** — envoyer l'URL et des captures (haut, milieu nuit, bas aube, logo, favicon) à l'utilisateur. Attendre sa validation avant Task 7.

---

### Task 7: Diorama 3D en direct

**Files:**
- Create: `site/scripts/fetch-models.mjs`, `site/src/scripts/diorama/island.ts`, `site/src/scripts/diorama/scene.ts`, `site/src/scripts/diorama/loader.ts`, `site/src/scripts/lighting.ts`
- Modify: `.gitignore` (`site/public/models/polyfork/`), `site/src/pages/index.astro`
- Test: `site/tests/unit/island.test.ts`, `site/tests/unit/lighting.test.ts`, `site/tests/unit/fetch-models.test.ts`, `site/tests/e2e/diorama.spec.ts`

**Interfaces:**
- Consumes: `shouldUse3D`, `readEnv`, `initScroll().onProgress` (Task 4), `nightFactor`, `dawnFactor` (Task 1).
- Produces:
  - `type Placement = { id: string; x: number; z: number; ry?: number; key?: string }`, `ISLAND: Placement[]`, `modelIds(): string[]` (ids uniques).
  - `fetchModels(ids: string[], dir: string, fetchImpl = fetch): Promise<void>` — rejette avec la liste des ids en échec.
  - `type Light = { background: string; hemiSky: string; hemiGround: string; hemiIntensity: number; sunColor: string; sunIntensity: number; sunElevationDeg: number; glow: number }`, `lightAt(night: number, dawn: number): Light` — `background` = `paletteAt(...).bg` correspondant ; `glow` = `night × (1 − dawn)`.
  - `createDiorama(canvas: HTMLCanvasElement, opts: { onReady(): void; onError(e: unknown): void }): { setProgress(p: number): void; setPointer(nx: number, ny: number): void; dispose(): void }`.
  - `mountDiorama(env: Env)` dans `loader.ts` : n'agit que si `shouldUse3D(env)` ; importe `scene.ts` dynamiquement après `requestIdleCallback` (repli `setTimeout` 1 s) ; passe `#diorama` à `data-state="live"` (fondu 600 ms) sur `onReady`, reste `poster` sur `onError` ou `webglcontextlost`.

- [ ] **Step 1: Tests qui échouent** — `island.test.ts` : chaque id existe dans la liste autorisée ci-dessous ; positions dans un disque de rayon 12 m ; au moins 1 `cherry-blossom-tree-3f7ab7`, 3 `pastel-flowering-plant-d16a03`, 3 `towering-cloud-2e00f1`. `lighting.test.ts` : `lightAt(0,0).background === '#f6f1e7'`, `lightAt(1,0).background === '#22203a'`, `lightAt(1,1).background === '#fbeee9'`, `glow` = 0 de jour, 1 de nuit, 0 à l'aube ; `sunElevationDeg` décroît de jour à nuit. `fetch-models.test.ts` : une réponse 404 sur un id → rejet contenant cet id ; tout 200 → fichiers écrits. e2e : avec WebGL (`--use-gl=swiftshader`), `#diorama[data-state="live"]` dans les 10 s et aucune erreur console ; avec `--disable-webgl` → reste `poster`, aucune erreur ; en reduced-motion → aucun `<canvas>`.
- [ ] **Step 2: Lancer** → FAIL.
- [ ] **Step 3: `island.ts`** — île faite maison (dalle low-poly ~24 m de diamètre, dessus prairie `#b9e4ad`, flancs terre `#a9795a`/`#8c6148`, petite mare `#9fd8e3`) + placements choisis parmi : `cherry-blossom-tree-3f7ab7`, `pastel-flowering-plant-d16a03`, `wildflower-plant-cf4279`, `fern-plant-1559b8`, `leafy-bush-d37bba`, `grass-tuft-62e90c`, `field-rock-5e37c6`, `towering-cloud-2e00f1` (nuages hors île, origine à `origin_y` 9). Aucun bâtiment. Le builder compose ; mesurer le total des GLB (≤ 4 Mo).
- [ ] **Step 4: `fetch-models.mjs`** télécharge `https://polyfork.dev/cdn/{id}.glb` pour `modelIds()` vers `public/models/polyfork/` ; ajouté au `Dockerfile` avant `npm run build`.
- [ ] **Step 5: `lighting.ts` + `scene.ts`** — `THREE.NoToneMapping`, sRGB ; caméra orthographique isométrique ; rotation lente de l'île (1 tour / 120 s), nuages qui dérivent ; `setProgress` règle `lightAt`, abaisse la caméra vers l'île (élévation 35° → 22°) active la luminescence des fleurs (`emissive` proportionnel à `glow`) et des lucioles (~40 points flottants, opacité = `glow`) ; `setPointer` = parallaxe ±3° ; survol d'une plante (raycast) → balancement amorti + 6 pétales en particules. `devicePixelRatio` plafonné à 2 ; rendu suspendu quand `#diorama` sort de l'écran (IntersectionObserver) ou onglet caché.
- [ ] **Step 6: Lancer** `npm run fetch:models && npx vitest run && npx playwright test` → PASS. Mesurer `du -sh public/models/polyfork` ≤ 4 Mo et le poids JS initial ≤ 80 Ko gzip (`dist/_astro`, hors chunk 3D).
- [ ] **Step 7: Commit** `feat(site): add live Polyfork diorama driven by scroll`.

---

### Task 8: Micro-interactions

**Files:**
- Create: `site/src/scripts/reveal.ts`, `site/src/scripts/cursor.ts`
- Modify: `site/src/components/Tools.astro`, `site/src/components/Countdown.astro`, `site/src/styles/global.css`
- Test: `site/tests/e2e/motion.spec.ts`

**Interfaces:**
- Consumes: `Env` (Task 4), `onProgress` (Task 4), `[data-logo-hand]` (Task 2).
- Produces: `initReveal(env)`, `initCursor(env)`.

- [ ] **Step 1: Tests qui échouent** — `motion.spec.ts` : avec un pointeur fin, `.cursor-net` existe et suit la souris ; en émulation tactile (`hasTouch: true, isMobile: true`), il n'existe pas ; en reduced-motion, les éléments `[data-reveal]` sont visibles (opacité 1) sans scroller ; la rotation de `[data-logo-hand]` à 50 % de progression vaut 180°.
- [ ] **Step 2: Lancer** → FAIL.
- [ ] **Step 3: Implémenter** — apparitions : montée 16 px + fondu, 500 ms, cascade 60 ms, une seule fois ; icônes d'outils : petite animation de geste au survol/focus (filet qui balaie, harpon qui part, fléchette) ; aiguille-feuille du logo : `rotate(progress × 360deg)` ; boutons : `scale(0.97)` à l'appui ; curseur-filet : uniquement `pointer: fine` et hors reduced-motion, curseur système conservé sur les champs de texte. Animer seulement `transform` et `opacity`.
- [ ] **Step 4: Lancer** → PASS.
- [ ] **Step 5: Commit** `feat(site): add micro-interactions`.

---

### Task 9: Poster, image OG, vérification finale et redéploiement

**Files:**
- Create: `site/scripts/render-poster.mjs`
- Generated (commités) : `site/public/poster.webp`, `site/public/og.png`
- Test: `site/tests/e2e/assets.spec.ts`

- [ ] **Step 1: Test qui échoue** — `poster.webp` existe, ≤ 200 Ko ; `og.png` fait 1200×630 ; `/og.png` et `/poster.webp` répondent 200 en preview.
- [ ] **Step 2: `render-poster.mjs`** — build + preview, Playwright avec WebGL (swiftshader), attend `data-state="live"` : capture de `#diorama` à progression 0 (→ `poster.webp`, qualité 80) et composition OG 1200×630 (diorama au crépuscule + logo horizontal + titre).
- [ ] **Step 3: Lancer** `npm run poster && npx playwright test tests/e2e/assets.spec.ts` → PASS.
- [ ] **Step 4: Suite complète** `npx vitest run && npx playwright test && npx astro check && npm run build` → tout vert.
- [ ] **Step 5: Commit + push**, redéployer via Coolify, puis vérifier en production : `curl -sI` 200 sur `/`, `/og.png`, `/favicon.ico`, `/models/polyfork/cherry-blossom-tree-3f7ab7.glb` ; capture Playwright de la production en haut, au milieu et en bas.
- [ ] **Step 6: Commit** `feat(site): add rendered poster and Open Graph image`.
