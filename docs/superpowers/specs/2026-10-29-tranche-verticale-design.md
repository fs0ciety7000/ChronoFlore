# ChronoFlore — Tranche verticale : design

Date : 2026-10-29 · Statut : validé par l'utilisateur

## 1. Intention

Prouver que la boucle de ChronoFlore est amusante et porte son ambiance avant d'investir dans l'art final : sur une île en diorama, une rêveuse lucide poursuit des plantes-émotions qui fuient, les ralentit, les capture au filet, et fait ainsi avancer sa nuit de 8 h de sommeil. Entre deux nuits, son herbier se remplit (fragments de souvenirs) et débloque des outils.

Ce que la tranche doit permettre de juger :
- la poursuite « ralentir puis capturer » est-elle satisfaisante au clavier-souris et à la manette ?
- la jauge de lucidité crée-t-elle assez de tension sans chronomètre ?
- la lumière qui suit la nuit (pastel → indigo → aube) suffit-elle à lire la progression ?
- l'envie de relancer une nuit pour remplir l'herbier existe-t-elle ?

## 2. Objectifs, non-objectifs, anti-objectifs

**Objectifs**
- Une île jouable, une nuit complète de bout en bout (début → réveil ou aube).
- 3 outils : filet et fusil tranquillisant dès le départ, harpon débloqué par la progression.
- 4 espèces : 3 plantes capturables au comportement de fuite distinct, 1 plante-cauchemar.
- Herbier persistant entre les nuits, avec un fragment de souvenir par espèce.
- Clavier-souris et manette.
- Export Web fonctionnel ; presets d'export Linux, Windows et macOS ajoutés.

**Non-objectifs (pour cette tranche)**
- Contrôles tactiles et interface mobile (conçus pour, construits juste après : voir § 6).
- Plusieurs îles, boss, améliorations d'outils, pétales bonus.
- Art final de l'héroïne et des plantes (placeholders stylisés).
- Musique et mixage audio (quelques SFX provisoires au plus).
- Localisation : l'interface est en français uniquement.
- Applications natives Android/iOS, signature/notarisation macOS.

**Anti-objectifs (ce qui ferait échouer la tranche même si elle « marche »)**
- Un jeu de tir exigeant : viser ne doit jamais être la difficulté principale.
- Une pression d'horloge qui empêche de profiter de l'île : le temps réel n'est pas une menace.
- Un échec punitif : perdre, c'est « se réveiller trop tôt », jamais un game over brutal.
- Une esthétique sombre ou réaliste : on reste kawaï même la nuit.

## 3. Contraintes

- Godot 4.7.2, GDScript typé, renderer Compatibility (Web, mobile plus tard).
- 3D, `Camera3D` orthographique, angle isométrique fixe.
- Assets 3D : catalogue Polyfork (GLB dans `game/assets/polyfork/<asset-id>/`) ou fait maison (`game/assets/custom/`), rien d'autre. Tailles réelles, origine au sol, pas de rescale pour tricher.
- Direction artistique : voir `AGENTS.md`. Cohérence avec le site : la nuit qui avance (diorama pastel → herbier indigo → réveil) et le logo « Fleur-horloge » (pétales rose/lavande en cadran, aiguille-feuille verte).
- Tests headless : `godot --headless --path game --script res://tests/test_runner.gd` doit passer à chaque étape.
- Export Web sans threads (preset existant).

## 4. Approches envisagées

1. **Gameplay d'abord, tout en primitives**, passe d'art à la fin. Le plus rapide pour valider la boucle, mais l'ambiance (qui fait partie de ce qu'on teste) arrive trop tard.
2. **Diorama d'abord** (île Polyfork, lumière, modèles faits maison), gameplay ensuite. Beau tôt, mais on investit dans l'art avant de savoir si capturer est amusant ; les plantes faites maison seraient refaites.
3. **Mélange** — retenu par l'utilisateur. Décor Polyfork dès le départ (peu coûteux), personnages stylisés provisoires en primitives, éclairage de nuit tôt car c'est l'horloge du jeu, et tout le contenu piloté par des données (`Resource`) pour remplacer l'art et ajouter des espèces sans toucher au code.

## 5. Game design (décidé)

Les points marqués *(proposition)* ont été remplis par Claude et acceptés en l'état pendant la discussion ; les chiffres sont des valeurs de départ à régler en jeu.

### 5.1 Boucle de capture

La plante repère l'héroïne et **fuit**. Le joueur la **ralentit**, puis la **capture**. Le filet est le seul outil qui capture.

| Outil | Rôle | Comportement *(proposition)* |
|---|---|---|
| Fusil tranquillisant | ralentir à distance | Fléchette (projectile). Chaque touche ajoute une charge de torpeur : −25 % de vitesse par charge. À 3 charges, la plante est **endormie** (immobile) 3 s. Une charge retombe toutes les 2,5 s sans touche. Munitions illimitées, cadence ~0,6 s. |
| Harpon | immobiliser | Débloqué par l'herbier. Projectile plus lent, recharge ~2,5 s. Une touche **cloue** la plante 3 s. |
| Filet | capturer | Coup en arc devant l'héroïne, portée ~2 m. Réussit si la plante porte **au moins 2 charges de torpeur** (≤ 50 % de sa vitesse), est endormie, clouée, ou est une Timidelle en train d'émerger. Sinon : raté, la plante s'affole (petit sprint). *(choix de Claude : 2 fléchettes suffisent avant le filet, pour que viser ne soit pas la difficulté principale.)* |

Visée assistée : un léger aimant oriente le tir vers la plante la plus proche dans un cône devant la visée. Il est plus fort à la manette qu'à la souris. Le mobile utilisera une visée entièrement automatique (§ 6).

### 5.2 La nuit : horloge et lucidité

Il n'y a pas de chronomètre en temps réel. Le HUD principal est la **fleur-horloge** du logo.

- **L'aiguille-feuille = l'heure de sommeil**, de 0 h à 8 h. Elle n'avance qu'avec les captures : commune +20 min, peu commune +40 min, rare +60 min *(proposition)*. Une nuit complète demande une vingtaine de captures.
- **Les pétales = la lucidité**, 5 au départ *(proposition)*. Un pétale tombe quand :
  - une plante alertée atteint le bord de l'île et saute dans le vide (elle s'échappe) ;
  - une plante-cauchemar touche l'héroïne (puis invulnérabilité ~1,5 s).
- **Repousse :** un pétale repousse après 3 captures d'affilée sans perte *(proposition)*.
- **Fin de nuit :**
  - dernier pétale tombé → **réveil en sursaut** à l'heure atteinte ;
  - aiguille à 8 h → **aube**, nuit complète. C'est la victoire, saluée par une séquence d'aube et un bonus : la nuit complète compte pour le record et révèle le prochain « souvenir d'aube » (§ 5.5).
- **La difficulté suit l'heure :** la vitesse des plantes augmente d'environ 8 % par heure. Les espèces peu communes apparaissent à partir de 2 h et les rares à partir de 4 h. Le nombre de cauchemars passe de 1 à 3 au fil de la nuit. Population cible : 6 à 8 plantes en jeu, réapparition progressive *(proposition)*.

### 5.3 Lumière = horloge visible

Un paramètre `night_progress` (0 → 1 = 0 h → 8 h) pilote la direction et la couleur de la `DirectionalLight3D`, la lumière ambiante et le fond :
- 0 h–2 h : diorama pastel de jour, fond crème uni ;
- 2 h–6 h : herbier indigo, les plantes émettent une lueur douce pour rester lisibles ;
- 6 h–8 h : aube rose et lavande.

La transition est continue et suit l'aiguille en douceur, sans saut à chaque capture.

### 5.4 Espèces de la tranche *(proposition, noms et textes provisoires)*

| Espèce | Émotion | Rareté | Fuite |
|---|---|---|---|
| **Rêvette** | joie légère | commune | Sprints courts en ligne droite, s'arrête souvent pour « respirer ». Plante d'apprentissage. |
| **Nostalgerbe** | nostalgie | commune | Zigzag. Se fige quand elle est hors du cône de visée de l'héroïne (direction de visée fournie : souris, stick droit, ou direction de marche / visée auto), repart dès qu'elle y entre ou que l'héroïne approche à < 4 m. *(choix de Claude)* |
| **Timidelle** | timidité | peu commune (≥ 2 h) | S'enterre quand l'héroïne approche et ressort 4 à 6 m plus loin. Pendant la seconde où elle émerge, le filet la capture même sans torpeur (énigme de timing ; état de capture « émergente »). Sous terre, elle est intouchable. *(choix de Claude)* |
| **Ronce-Angoisse** | angoisse (cauchemar) | dès 0 h, plus nombreuse la nuit | Ne fuit pas : avance lentement vers l'héroïne. Le contact coûte un pétale. Elle ne se capture pas, mais le tranquillisant l'endort. |

Une espèce rare (≥ 4 h, +60 min) est prévue au système mais pas obligatoire dans la tranche : les quatre ci-dessus suffisent.

### 5.5 Progression entre les nuits

- **Herbier :** chaque espèce a une page avec son nom, son émotion, le nombre de captures et un **fragment de souvenir** (2 à 3 phrases) révélé à la découverte. Deux **détails** supplémentaires (1 phrase chacun) se révèlent à 5 et 15 captures cumulées de l'espèce. La page de la Ronce-Angoisse s'obtient en l'endormant une première fois ; ses détails, à 5 et 15 endormissements. *(choix de Claude)*
- **Souvenirs d'aube :** une suite ordonnée de fragments partagés (3 dans la tranche). Chaque nuit complète révèle le suivant, une fois chacun ; quand tous sont lus, la nuit complète ne compte plus que pour le record. *(choix de Claude)*
- **Paliers de déblocage** (données, extensibles) : 3 espèces **capturables** découvertes → harpon. La Ronce-Angoisse ne compte pas : il faut avoir atteint 2 h et capturé une Timidelle, ce qui fait du harpon la récompense d'une première bonne nuit. *(choix de Claude)* Le système accepte d'autres types de récompense plus tard (pétale bonus, amélioration d'outil).
- **Écran de réveil :** heure atteinte, captures de la nuit, nouvelles pages, déblocage obtenu, record.
- **Sauvegarde locale** : espèces découvertes, compteurs par espèce, outils débloqués, meilleure heure, nuits complètes, index du prochain souvenir d'aube. Un réveil en sursaut sauvegarde aussi la progression de la nuit (rien n'est perdu). Le JSON porte un champ `version`.
- Les fragments sont écrits en provisoire par le builder ; l'utilisateur les réécrira.

### 5.6 Contrôles

| Action | Clavier-souris | Manette |
|---|---|---|
| Se déplacer | ZQSD / WASD / flèches | stick gauche |
| Viser | souris (position au sol) | stick droit (sinon : direction de marche) |
| Utiliser l'outil | clic gauche | gâchette droite |
| Changer d'outil | molette / 1-2-3 | gâchettes hautes (bumpers) |
| Pause / herbier | Échap | Start |

Tout passe par l'InputMap (actions nommées) pour ajouter le tactile sans toucher au gameplay.

### 5.7 Caméra et île

- Caméra orthographique iso fixe qui suit l'héroïne avec lissage et reste bornée à l'île.
- Île d'environ 40 × 45 m. Les bords en coupe de terre sont la limite : l'héroïne ne peut pas tomber, les plantes oui (c'est leur fuite).
- Décor Polyfork. Piste d'île principale : `steampunk-farm-terrain-98cb8a` (« Sky Town Terrain », 46 × 50,5 m, bords d'île en coupe de terre, couleurs réglables via ses knobs, 25 k triangles). Végétation et décor de rêve tirés de `nature-forest-kit-f29d6a` et `insect-world-e44b9f` : ce dernier est à l'échelle ×100, donc ses pâquerettes de 8 m et ses champignons de 7 m deviennent des plantes géantes oniriques autour d'une héroïne de taille réelle. Pas de bâtiments steampunk.

### 5.8 Écrans

Titre (Commencer la nuit / Herbier / Quitter) → Nuit (jeu + HUD) → Réveil (bilan) → retour titre ou nuit suivante. Pause en jeu avec accès à l'herbier. HUD minimal en cartouches crème arrondies : fleur-horloge, outil actif, notification de capture.

### 5.9 Placeholders

- **Héroïne :** chibi en primitives aux bonnes couleurs (peau foncée, tresses noires, lunettes rondes roses, haut rayé vert/rouge/orange/violet, collier doré), avec squash & stretch à la marche.
- **Plantes :** primitives pastel et une silhouette distincte par espèce. Animations procédurales : rebond, tremblement quand elles sont alertées, affaissement quand elles sont endormies.
- Chaque visuel est une sous-scène remplaçable sans toucher au code.

## 6. Préparer le tactile (construit juste après la tranche)

- Joystick virtuel à gauche, gros boutons d'outil à droite.
- Visée automatique sur la plante la plus proche devant l'héroïne.
- Conséquence pour la tranche : la logique de visée doit accepter une **direction fournie** (souris, stick ou auto) et la visée assistée doit fonctionner seule. Aucune règle de gameplay ne doit dépendre de la souris.

## 7. Architecture technique *(proposition de Claude, ajustable par le builder)*

- **Données (`Resource` + `.tres`)** : `PlantSpecies` (nom, émotion, rareté, minutes gagnées, vitesse, comportement de fuite, heure d'apparition, scène visuelle, fragment), `ToolData` (cadence, portée, effet), `UnlockMilestone` (seuil d'espèces, récompense). Une nouvelle espèce = un nouveau `.tres` + une scène visuelle.
- **Logique pure, testable headless** (classes `RefCounted`, sans nœuds) :
  - `NightClock` : minutes, captures, progression 0..1, fin à 8 h ;
  - `Lucidity` : pétales, perte, repousse, épuisement ;
  - `Herbarium` : découvertes, compteurs, paliers ;
  - `SaveData` : sérialisation ;
  - règles de capture : la plante est-elle capturable selon son état ?
- **Autoload `GameState`** : l'herbier et la sauvegarde courante, persistés entre les scènes.
- **Plantes :** `CharacterBody3D` avec une petite machine à états (errance → alerte → fuite → ralentie/endormie/clouée → capturée/échappée) et un pilotage simple (s'éloigner de l'héroïne, détourner du bord sauf en panique). Pas de NavigationServer dans la tranche.
- **Communication par signaux :** `plant_captured`, `plant_escaped`, `petal_lost`, `night_ended`. Le HUD écoute et n'interroge pas.
- **Sauvegarde :** JSON dans `user://save.json` (fonctionne en Web via IndexedDB). Sauvegarde à la fin de chaque nuit.

## 8. Tests

- Unitaires headless dans `tests/test_runner.gd` (ou fichiers de test appelés par lui) pour `NightClock`, `Lucidity`, `Herbarium` (paliers, déblocage du harpon), aller-retour `SaveData`, règles de capture et torpeur (empilement, retombée, sommeil).
- Smoke test : la scène principale se charge en headless sans erreur.
- Vérification manuelle : une nuit complète jouée au clavier-souris et à la manette ; export Web lancé dans un navigateur.

## 9. Laissé au builder

- Le réglage fin de tous les chiffres marqués *(proposition)*.
- Le choix final des assets Polyfork de décor et leur placement : il faut vérifier que les couleurs de sommets des GLB s'importent bien dans Godot (matériau en `vertex_color_use_as_albedo`) et ajuster le knob de couleur de l'île vers le pastel si nécessaire.
- Les noms et formes définitifs des placeholders, les textes provisoires des fragments.
- L'organisation exacte des dossiers sous `game/scenes` et `game/scripts`.
- L'ordre de construction, défini dans le plan d'implémentation.
