# Site vitrine et logo ChronoFlore — design

Date : 2026-10-29 · Statut : à valider. Le plan d'implémentation prévoit un point de contrôle visuel (logo + page statique) avant le gros du travail 3D.

## Intention

Présenter ChronoFlore avant que le jeu n'existe visuellement, et donner envie de **découvrir et partager** l'univers. Le visiteur n'a rien à acheter ni à laisser : il comprend le rêve, la chasseuse, les plantes-émotions, et repart avec un lien à faire circuler.

Le site doit paraître **premium** : ouverture cinématique en 3D et micro-interactions soignées. La DA du site raconte la nuit : on arrive de jour (l'endormissement), le scroll fait tomber la nuit au rythme du compte à rebours `02:00:00`, et le bas de page s'éclaire au réveil.

## Objectifs

- Une page unique, en français, sur `https://chronoflore.cardormedia.com`.
- Une ouverture plein écran : un diorama 3D flottant, rendu en direct (three.js), assets Polyfork, qui vit (balancement, nuages, lucioles) et réagit au pointeur.
- Le scroll pilote la caméra, l'heure de la scène (jour → nuit) et la palette de toute la page.
- Le logo « Fleur-horloge » (piste A) décliné pour le site et le jeu.
- Partage en un geste : Web Share API sur mobile, copier le lien, liens Bluesky, X, Facebook, et une image Open Graph soignée.

## Non-objectifs

- Pas de collecte d'email, de compte, de backend, d'analytics tierce.
- Pas de trailer vidéo ni d'outil Hyperframes.
- Pas d'export Web du jeu Godot intégré (39 Mo de wasm avant le premier pixel).
- Pas de version anglaise pour l'instant.

## Anti-objectifs (échec même si « ça marche »)

- Un site qui ressemble à un template (dégradés génériques, cartes à bordure gauche, emoji).
- Une ouverture qui saccade, ou un écran blanc pendant le chargement de la 3D.
- Une page illisible ou inutilisable sans 3D, au clavier, ou avec « réduire les animations ».
- Des visuels qui contredisent la DA du jeu (assets hors Polyfork ou hors fait-maison).

## Contraintes

- Stack fixée : Astro 5 statique dans `site/`, servi par nginx (`site/Dockerfile`) sur Coolify (`coolify.fs0ciety.org`). DNS Cloudflare : `chronoflore.cardormedia.com` vers `COOLIFY_SERVER_IP`. Accès API dans l'environnement (`.env.example`).
- Assets 3D : Polyfork uniquement (GLB/`.mjs` autohébergés dans le site, autorisé par la licence Polyfork pour un site qui les contient) ou faits maison. Pas de rescale pour faire coller une taille.
- Accès Polyfork : compte gratuit, clé déjà branchée sur le MCP `polyfork` de la session (`who_am_i` : authentifié, plan free). Tout modèle low poly est gratuit : `https://polyfork.dev/cdn/{id}.glb` sans clé ; le zip d'un kit (avec `kit.mjs`, `stage.mjs`, `terrain.mjs`, `LAYOUT.json`) se télécharge avec la clé gratuite, via l'URL signée que renvoie `get_kit`. Aucun achat nécessaire. Les éditions HD (Pro) sont exclues.
- Éclairage Polyfork : pas de tone mapping ACES à l'exposition 1 sur ces modèles (rendu un tiers plus sombre). Utiliser `stage.mjs` du kit, ou reproduire ses réglages.
- L'héroïne n'est pas encore modélisée : aucune image d'elle n'est inventée ; un emplacement réservé (`[Rendu 3D de l'héroïne — à venir]`) tient sa place.
- Budget : poster de l'ouverture affiché < 1,5 s en 4G ; 3D chargée en différé ; GLB cumulés ≤ 4 Mo ; 60 fps visés sur un portable récent, dégradation propre sur mobile.
- Accessibilité : contrastes AA dans les deux ambiances, navigation clavier, `prefers-reduced-motion` respecté, canvas 3D décoratif (`aria-hidden`) avec le texte dans le DOM.

## Approches envisagées

1. **Diorama 3D en direct + animations au scroll** — retenue. Rendu temps réel three.js, assets Polyfork, scroll qui pilote caméra/heure/palette, repli image fixe. Vivant et interactif, même DA que le jeu ; plus de travail, performance mobile à surveiller.
2. **Séquence d'images pré-rendue lue au scroll.** Fluide partout et léchée, mais aucune interaction, et chaque changement impose un nouveau rendu.
3. **Hybride (pré-rendu puis 3D en direct).** Meilleur premier affichage, deux pipelines à maintenir.

Écartée d'emblée : embarquer l'export Web Godot (poids rédhibitoire).

Choix de l'utilisateur : **approche 1**, pour un diorama qu'on peut toucher, qui se partage mieux qu'une vidéo. Le repli image fixe couvre les appareils modestes.

## Ce qui est décidé

### Récit de la page (jour → nuit → réveil)

**Source de vérité des textes et du logo** : les maquettes validées, copiées dans `docs/superpowers/specs/mockups/` (`Main.dc.html` = logos, `SiteJour.dc.html`, `SiteNuit.dc.html`) et publiées sur https://claude.ai/artifact/6KYT7A9KJZMknvjEW2EXBy. Reprendre leurs textes tels quels (accroche, paragraphes, outils, spécimens) et la géométrie SVG exacte de la piste A. Les spécimens : les quatre de la maquette jour, avec les noms latins de la maquette nuit pour les trois qui en ont ; le quatrième (« Souvenir d'été ») reçoit un nom latin du même ton (avis du builder).

Une seule page, sections dans cet ordre :

| # | Section | Heure de la scène | Contenu |
|---|---|---|---|
| 0 | Ouverture | jour (`setTime 0`) | Logo, titre « Deux heures de sommeil. Toute une flore à capturer. », phrase d'accroche, boutons « Partager le rêve » et « Découvrir l'histoire ». Diorama plein écran derrière. |
| 1 | Compte à rebours | jour → doré | Bandeau `02:00:00` dont l'heure avance avec le scroll jusqu'à `00:00:00` en bas de page. |
| 2 | Le rêve | doré → crépuscule | Deux paragraphes ; la caméra plonge vers l'île. |
| 3 | La chasseuse | crépuscule | Emplacement réservé héroïne + texte (tresses, lunettes roses, haut rayé, besace d'herboriste). |
| 4 | Les outils | crépuscule → nuit | Filet, harpon, fusil tranquillisant, chacun avec une icône animée au survol. |
| 5 | L'herbier | nuit | Planches de spécimens façon herbier (n°, nom latin, nom commun, une ligne). Noms marqués comme exemples tant que le game design ne les a pas fixés. |
| 6 | Réveil / partage | aube (`dawn`) | La lumière revient, « Fais circuler le rêve », boutons de partage. |
| 7 | Pied de page | aube | « ChronoFlore · un jeu cardormedia », domaine. |

La palette CSS de la page interpole entre deux jeux de jetons, **jour** (crème `#f6f1e7`, encre `#3b3350`, rose `#f4b9c8`, lavande `#cdc4ef`, menthe `#8fcf9f`) et **nuit** (indigo `#22203a`, texte `#ede8fb`, rose `#f7c3d2`), puis repasse en clair à l'aube.

### Ouverture cinématique

- Une île-diorama **composée pour ChronoFlore**, pas le village Sky Town tel quel : terrain d'île flottante (programme de terrain d'un kit Polyfork ou socle fait maison), avec des pièces choisies dans le catalogue : arbres, fleurs pastel (ex. « Pastel Flowering Plant »), herbes, rochers, nuages. Pas de bâtiments industriels.
- Fond crème qui s'assombrit avec la scène ; nuages flottants ; l'île tourne très lentement.
- Pointeur : légère parallaxe de caméra ; survol d'une plante = elle se balance et émet quelques pétales.
- Le scroll fait descendre la caméra vers l'île et appelle `look.setTime(t)` de `stage.mjs` (0 = jour → 1 = nuit), puis `dawn` en fin de page. La nuit, les plantes deviennent luminescentes.
- Chargement : un **poster** (rendu de la même scène) s'affiche immédiatement ; la 3D se charge après le premier affichage, puis remplace le poster en fondu quand elle est prête.

### Micro-interactions

- Curseur personnalisé en petit filet sur pointeur fin (désactivé au tactile).
- Apparitions au scroll (montée douce + fondu) des titres et cartes, en cascade courte.
- Aiguille-feuille du logo qui tourne avec le compte à rebours.
- Boutons : retour tactile (léger rebond à l'appui), « Copier le lien » confirme sans modale.
- Défilement fluide (inertie) sur pointeur fin uniquement.
- Avec « réduire les animations » : pas de défilement fluide, pas de mouvement de caméra, scène figée en image fixe par section ; le changement de palette reste en fondu simple.

### Logo « Fleur-horloge » (piste A)

- Symbole : six pétales roses `#f4b9c8` alternés de six pétales lavande `#cdc4ef`, cadran crème cerclé d'encre `#3b3350`, une aiguille et une aiguille-feuille menthe `#8fcf9f`.
- Logotype : « Chrono » encre + « Flore » rose soutenu, Fredoka SemiBold.
- Livrables dans `branding/` : SVG maître (symbole + logotype, horizontal et empilé), symbole seul, version monochrome encre et monochrome crème, favicon SVG + ICO, `apple-touch-icon` 180 px, PNG 512/1024, icône Godot (`game/icon.svg` référencée dans `project.godot`), image Open Graph 1200×630.
- Le symbole doit rester lisible à 16 px.

### Typographie

Fredoka (titres, logotype), Nunito (texte), Fraunces italique pour les légendes de planches de la partie nuit. Polices autohébergées (pas d'appel à Google Fonts en production).

### Déploiement

- L'utilisateur a autorisé explicitement le déploiement et la création du sous-domaine : le builder exécute ces étapes lui-même (pas seulement les préparer).
- Application Coolify construite depuis `site/Dockerfile` (dépôt `fs0ciety7000/ChronoFlore`, répertoire de base `site/`), domaine `chronoflore.cardormedia.com`, HTTPS par Coolify (Let's Encrypt).
- Branche déployée : `claude/focused-cerf-d2kgbx` tant que le travail n'est pas fusionné, puis `master` après fusion. *(choix de Claude)*
- Enregistrement DNS Cloudflare `A chronoflore` dans la zone `cardormedia.com` vers `COOLIFY_SERVER_IP`, **DNS only (nuage gris)**, pour que Coolify obtienne son certificat sans conflit de mode SSL. Passer en proxy plus tard est possible en mode SSL « Full (strict) ». *(choix de Claude)*
- Ne rien modifier d'autre dans la zone Cloudflare ni dans Coolify (autres apps, autres enregistrements).
- Cache long sur les assets fingerprintés, `index.html` sans cache long.
- Vérification finale : la page répond en HTTPS sur le domaine, avec la 3D et le repli.

## Laissé au builder

- Le choix exact des pièces Polyfork et la composition de l'île, dans le respect de la DA et du budget.
- La bibliothèque d'animation au scroll et de défilement fluide.
- La façon de générer le poster et l'image Open Graph (rendu headless de la scène recommandé, pour qu'ils correspondent à la 3D).
- La structure des composants Astro et le découpage du code.
