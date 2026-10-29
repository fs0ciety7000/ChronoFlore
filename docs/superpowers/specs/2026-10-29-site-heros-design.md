# Site vitrine — intégration de l'héroïne et du compagnon

Date : 2026-10-29 · Statut : validé par l'utilisateur · Complète `2026-10-29-site-vitrine-logo-design.md`

## Intention

Les modèles 3D faits maison de l'héroïne et du héros sont terminés (branche `claude/chronoflore-game`). Le site doit les montrer : la chasseuse remplace son emplacement vide, le héros (« le compagnon » en attendant un nom) a sa propre planche, et le duo apparaît sur l'île du diorama.

## Sources

- `game/assets/custom/heroine/heroine.glb` et `game/assets/custom/hero2/hero2.glb` de la branche `origin/claude/chronoflore-game` (≈ 370 Ko chacun, ~1,1 m, origine aux pieds, mêmes os, actions `Idle`, `Walk`, `Swing`, `Hurt`). Faits maison : ils sont **commités** dans le site (contrairement aux GLB Polyfork), sous des noms versionnés par hash (cache `immutable` sur `/models/`).
- Ne pas modifier `game/` ni la branche du jeu.

## Ce qui est décidé

### Planche II « La chasseuse »
- L'emplacement `[Rendu 3D de l'héroïne — à venir]` devient un **portrait 3D vivant** de l'héroïne : boucle `Idle`, rotation lente et légère (oscillation, pas un tour complet qui montrerait le dos trop longtemps), geste `Swing` (le filet) au survol ou au focus de la carte, puis retour à `Idle`.
- Texte de la planche inchangé.

### Nouvelle planche « Le compagnon » (Planche III ; les suivantes sont renumérotées : outils IV, herbier V)
- Même mise en page que la chasseuse, en miroir (portrait à droite sur desktop), même portrait 3D vivant avec le héros.
- Texte (exact) :
  - Légende : « Planche III »
  - Titre : « Le compagnon »
  - Paragraphe 1 : « Casquette de tweed, veste kaki, sourire en coin : il n'est pas réel, et il le sait. C'est une figure de son rêve, quelqu'un qu'elle a fait venir dans sa nuit pour ne pas la traverser seule. »
  - Paragraphe 2 : « Joue-le seul, ou à deux en coop locale : la nuit, les pétales et l'herbier restent les siens. »
- Ancre `#compagnon`, ajoutée à la navigation après « La chasseuse ».

### Le duo sur l'île du diorama
- Les deux personnages, à l'échelle réelle (aucun rescale), se promènent sur l'île : animation `Walk` le long d'un chemin doux autour de la mare, `Idle` aux pauses ; ils restent proches l'un de l'autre. Ils suivent la lumière jour → nuit comme le reste de la scène.
- Mobile : mêmes règles de dégradation que l'île (pas d'ombres, DPR plafonné).

### Portraits 3D : contraintes
- Un seul `WebGLRenderer` partagé pour les deux portraits (ou rendu dans le canvas existant via scissor/viewport) : jamais plus de 2 contextes WebGL sur la page.
- Rendu seulement quand le portrait est visible (IntersectionObserver), pause onglet caché.
- Chargés en différé avec le chunk 3D ; le JS initial reste ≤ 80 Ko gzip.
- Sans 3D (WebGL absent, échec de chargement, reduced-motion, `shouldUse3D` faux) : **image fixe** rendue depuis les vrais modèles (pose Idle, 3/4 face), WebP, ≤ 80 Ko chacune, générée par le script de rendu existant (`npm run poster`) et commitée ; `alt` descriptif. Reduced-motion : image fixe, pas d'animation.
- Contraste et dégagement du texte : les tests existants (balayage de contraste sur tous les nœuds texte, « copy clear of the island ») restent verts ; le cadre du portrait garde le fond `--field` et le texte `--on-field`.
- Accessibilité : canvas `aria-hidden`, la carte porte un `role="img"` + `aria-label` (« L'héroïne en 3D : peau foncée, longues tresses, lunettes roses, haut à rayures » / « Le compagnon en 3D : casquette de tweed grise, veste kaki, barbe courte »).

## Laissé au builder
- Le chemin de promenade exact sur l'île et la mise en scène des portraits (cadrage, éclairage), dans la DA pastel.
- L'organisation du code (module `portraits.ts` ou extension de `diorama/`).
