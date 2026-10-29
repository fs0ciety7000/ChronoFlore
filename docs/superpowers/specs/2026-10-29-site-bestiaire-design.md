# Site vitrine — l'herbier passe au vrai bestiaire (12 plantes)

Date : 2026-10-29 · Statut : validé par l'utilisateur · Complète `2026-10-29-site-vitrine-logo-design.md` et `2026-10-29-site-heros-design.md`

## Intention

La Planche V « L'herbier des émotions » montre encore 4 espèces d'exemple dessinées à la main. Le jeu a maintenant son bestiaire : 12 plantes-émotions modélisées maison (7 gentilles, 5 « monstres plantes » hostiles), avec vignettes rendues et textes (provisoires). Le site les reprend.

## Sources (branche `origin/claude/chronoflore-game`, sans la modifier)

- Données : `game/data/species/<id>.tres` → `display_name`, `emotion`, `rarity` (0 commune, 1 peu commune, 2 rare), `min_hour`, `fragment`.
- Hostiles (spec du jeu `docs/superpowers/specs/2026-10-29-bestiaire-design.md`) : `ronce_angoisse`, `croque_colere`, `lierre_jalousie`, `ortie_regret`, `champi_panique`. Les 7 autres sont gentilles.
- Vignettes : `game/assets/custom/plants/thumbs/<id>.png` (192×192, fond transparent). À convertir en WebP pour le site.
- Ordre d'affichage (numéros N° 001 → 012) : gentilles par heure d'apparition puis rareté — Rêvette, Nostalgerbe, Câlinette, Souffloine, Timidelle, Mélancolys, Lumiole ; puis hostiles par heure — Ronce-Angoisse, Croque-Colère, Lierre-Jalousie, Ortie-Regret, Champi-Panique.

## Ce qui est décidé

- **Données du site** : un module `site/src/data/bestiary.ts` (12 entrées typées : `id`, `name`, `emotion`, `rarity`, `fromHour`, `hostile`, `fragment`, `image`), recopié des `.tres` avec un commentaire indiquant la source. Le préfixe « (provisoire) » est retiré de chaque texte ; une seule mention globale le remplace.
- **Mise en page de la Planche V** :
  - Titre inchangé « L'herbier des émotions ».
  - La mention « [Espèces d'exemple — à définir avec le game design] » devient la pastille « Textes provisoires — le bestiaire pousse avec le jeu ».
  - Deux groupes avec sous-titre : « Les douces — à cueillir au filet » (7) et « Les monstres plantes — à endormir avant de les cueillir » (5).
  - Chaque planche-carte : vignette (image, `alt` = « {Nom}, plante de la {émotion} » ; pour une émotion au masculin ou commençant par une voyelle, accorder : « de l'espoir », « de l'angoisse »…), « N° 0XX » en Fraunces italique, nom (titre de carte), émotion, une pastille de rareté (« commune », « peu commune », « rare ») et « dès {h} h » quand `fromHour > 0` (sinon « dès la tombée du sommeil »). Les hostiles ont un repère visuel discret (petite épine / pastille « hostile »), mignon, jamais effrayant.
  - Le fragment complet est dans un `<details>` « Lire la page » sous chaque carte (accessible au clavier, fermé par défaut), pour garder la grille légère.
  - Les 4 illustrations SVG dessinées à la main et les noms latins sont retirés.
- **Grille** : 4 colonnes desktop, 2 en tablette, 1-2 sur mobile ; reste dans la colonne de texte (la couloir droite de l'île reste libre : test « copy clear of the island » vert).
- **Contraste** : tout texte des cartes ≥ 4.5:1 à chaque position de scroll (le balayage e2e de tous les nœuds texte couvre les cartes et les `<details>` ouverts — ajouter une étape qui ouvre un `<details>`).
- **Poids** : vignettes WebP ≤ 15 Ko chacune, chargées en `loading="lazy"` avec `width`/`height` (pas de décalage de mise en page).
- **Micro-interactions** : les cartes gardent l'apparition au scroll existante ; au survol/focus de la carte, la vignette fait un petit rebond (transform seulement, rien en reduced-motion).

## Laissé au builder

- Teintes pastel de fond des cartes (dans la palette existante), forme exacte du repère « hostile ».
