# Bestiaire de plantes faites maison — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** 12 espèces de plantes, chacune avec son modèle Blender fait maison et son comportement : 7 gentilles à capturer, 5 hostiles qui attaquent, s'endorment et se capturent endormies.

**Architecture :**
- On garde l'architecture de la Tâche 8 : `Plant` (machine à états), des scripts `behavior_*.gd` courts et des données dans les `.tres`.
- Les attaques à distance sont des scènes de danger réutilisables, chacune avec un signe au sol avant l'impact.
- Les modèles sont générés par des scripts bpy dans `game/assets/custom/plants/`.

**Tech Stack :** Godot 4.7.2, GDScript typé, Blender 5.2 (bpy) dans le venv du scratchpad.

**Spec :** `docs/superpowers/specs/2026-10-29-bestiaire-design.md` (validée). Elle complète `2026-10-29-tranche-verticale-design.md`.

**Ordre global (décidé par l'utilisateur) :**
1. corrections de la Tâche V ;
2. coup de filet (Tâche S) ;
3. intégration du héros (C1) ;
4. **ce plan (B1 → B4)** ;
5. écran de choix (C2) ;
6. coop (C3).

## Global Constraints

- Les contraintes globales du plan `2026-10-29-tranche-verticale.md` s'appliquent toutes : GDScript typé, Compatibility, modèles faits maison, commande de test, trailers, ne pas toucher `site/` ni `branding/`.
- **Modèles :**
  - un script bpy déterministe par lot, commité à côté de ses GLB : `game/assets/custom/plants/build_plants.py` → `game/assets/custom/plants/<id>/<id>.glb` ;
  - matériaux nommés avec couleur de base (pas de vertex colors) ;
  - 800 à 2 500 triangles par espèce ;
  - origine au sol, face +Z dans Godot ;
  - animations nommées `Idle`, `Move`, `Sleep`, `Caught`, plus `Attack` pour les hostiles ; `Idle` et `Move` bouclent.
- **Style :**
  - pastel, kawaï, avec un visage expressif (yeux, bouche) ;
  - les hostiles sont « mignonnes mais menaçantes » : sourcils froncés, petites dents, jamais gore ni effrayantes ;
  - hauteur de 0,5 à 1,0 m (lisible à la caméra de taille 10) ;
  - même éclairage que l'héroïne, avec un léger éclat propre de 0,2.
- **Lisibilité :** toute attaque hostile est annoncée au sol au moins 0,6 s avant l'impact.
- **Valeurs** (spec §2-§3) :
  - récompenses : commune 20, peu commune 40, rare 60, hostile endormie capturée 40 ;
  - 3 fléchettes endorment ;
  - recul 1,5 m et étourdissement 1 s après un coup ;
  - apparition : Câlinette 0 h, Souffloine 1 h, Timidelle 2 h, Croque-Colère 2 h, Mélancolys 3 h, Lierre-Jalousie 3 h, Lumiole 4 h, Ortie-Regret 4 h, Champi-Panique 5 h ; Rêvette, Nostalgerbe et Ronce dès 0 h.
- **Réglages proposés**, en constantes nommées, à affiner au playtest :
  - Câlinette : approche jusqu'à 2,5 m, puis bond de 4 m ;
  - Souffloine : bonds de 3 m, 0,7 s en l'air, capture impossible en l'air ;
  - Mélancolys : 2,2 m/s vers l'étang, cachée 4 s dans l'eau ;
  - Lumiole : 6 m/s, vol à 0,8 m (le filet l'atteint) ;
  - Croque-Colère : charge à 9 m/s sur 6 m, toutes les 4 s ;
  - Lierre-Jalousie : cercle de rayon 1,2 m, immobilise 1 s, toutes les 5 s ;
  - Ortie-Regret : épine en arc, portée 7 m, toutes les 3 s ;
  - Champi-Panique : nuage de rayon 2,5 m, ralentit à 50 % pendant 2 s, éclate toutes les 6 s.

## Review Focus

1. **Une hostile endormie qui se réveille pendant le coup de filet** : la capture ne compte que si la plante était endormie au moment du coup (pas de capture « au réveil »). *Tâche B3.*
2. **Plusieurs dangers sur l'héroïne en même temps** (épines + lianes + spores) : un seul pétale par fenêtre d'invulnérabilité. Immobilisation et ralentissement ne s'additionnent pas indéfiniment : on garde le plus long, sans cumul. *Tâche B3.*
3. **Mélancolys près de l'étang alors que l'héroïne est juste au bord** : elle ne doit pas rester bloquée ni traverser l'héroïne, et elle ne doit jamais apparaître dans l'eau. *Tâche B2.*
4. **Souffloine qui bondit au-dessus du bord de l'île** : un bond ne doit jamais l'emmener hors du contour, sauf si elle est en panique. *Tâche B2.*
5. **Un vieux fichier de sauvegarde** (avec 4 espèces) chargé avec le nouveau catalogue (12 espèces) : rien ne casse, les nouvelles pages sont simplement inconnues. *Tâche B4.*

---

### Task B1 : Modèles Blender des 4 espèces existantes

**Files :**
- Create : `game/assets/custom/plants/build_plants.py`, `game/assets/custom/plants/{revette,nostalgerbe,timidelle,ronce_angoisse}/*.glb`
- Create : `game/scenes/plants/visuals/plant_model_visual.gd` (base commune), puis remplace les 4 `visuals/*.tscn` à primitives
- Modify : `game/scenes/plants/plant.gd`, pour piloter les animations selon l'état : WANDER/ALERT → Idle, FLEE/PANIC → Move, endormie → Sleep, CAPTURED → Caught
- Test : `game/tests/unit/test_plant_models.gd`

**Interfaces — Produces :**
`plant_model_visual.gd` : `class_name PlantModelVisual extends Node3D`, avec `func play_state(state: Plant.State, asleep: bool) -> void` et `func set_glow(value: float) -> void`. `Plant` appelle ces deux méthodes. La signature de `set_glow` existante est conservée.

- [ ] **Step 1 :** test `test_each_species_model_has_animations` : pour les 4 espèces, `visual_scene` s'instancie, l'`AnimationPlayer` contient Idle/Move/Sleep/Caught (plus Attack pour la Ronce), et Idle/Move bouclent.
- [ ] **Step 2 :** lance le test. Attendu : FAIL.
- [ ] **Step 3 :** écris le générateur. Itère au moins 2 fois sur des rendus Godot réels (xvfb, voir le ledger) à la caméra de taille 10, avec les PNG dans `scratchpad/preview/plants_b1/`, puis branche les visuels.
- [ ] **Step 4 :** suite complète verte.
- [ ] **Step 5 :** commits `Add hand-made models for the four existing plant species` et `Drive plant animations from plant state`.

### Task B2 : Les 4 nouvelles gentilles

**Files :**
- Modify : `game/scripts/data/plant_species.gd` (Behavior + `SHY_APPROACH`, `HOPPER`, `POND_SEEKER`, `FLOATER`)
- Create : `game/scripts/plants/behavior_shy_approach.gd`, `behavior_hopper.gd`, `behavior_pond_seeker.gd`, `behavior_floater.gd`
- Create : `game/data/species/{calinette,souffloine,melancolys,lumiole}.tres`, ajoutés au catalogue
- Modify : `build_plants.py` (4 modèles de plus), et `IslandShape`/l'île si l'étang doit être exposé comme zone « eau »
- Test : `game/tests/unit/test_new_gentle_plants.gd`

**Interfaces :**
- Consumes : l'API de `Plant` (Tâche 8) et `IslandShape.obstacles` (Tâche V, l'étang).
- Produces :
  - `IslandShape.water_zones()` (ou réutilisation documentée de l'obstacle de l'étang) ;
  - `Plant.is_airborne() -> bool`, avec un filet qui rate une plante en l'air ;
  - `Plant.is_hidden() -> bool`, vrai pour Mélancolys dans l'eau, et qui ignore les outils.

- [ ] **Step 1 : tests.**
  - `test_calinette_approaches_then_hops_back` : distance qui diminue jusqu'à 2,5 m, puis bond qui l'éloigne de plus de 3 m.
  - `test_souffloine_uncatchable_airborne`.
  - `test_souffloine_never_leaves_island_unless_panic` *(Review Focus 4)*.
  - `test_melancolys_hides_in_pond_and_ignores_tools`.
  - `test_melancolys_never_spawns_in_water` *(Review Focus 3)*.
  - `test_lumiole_rare_reward_60`.
  - `test_new_species_spawn_hours` : chaque espèce respecte son heure d'apparition.
- [ ] **Step 2 :** lance les tests. Attendu : FAIL.
- [ ] **Step 3 :** implémente, avec des rendus réels des 4 nouveaux modèles dans `scratchpad/preview/plants_b2/`.
- [ ] **Step 4 :** suite complète verte.
- [ ] **Step 5 :** commits par sous-sujet : comportements, données, modèles.

### Task B3 : Les hostiles, leurs dangers, et la capture endormie

**Files :**
- Modify : `plant_species.gd` (champ `hostile: bool` ; Behavior + `CHARGER`, `ROOT_TRAP`, `SPITTER`, `SPORE`), `ronce_angoisse.tres` (`hostile = true`), `plant.gd` (capture d'une hostile endormie)
- Create : `game/scripts/plants/behavior_charger.gd`, `behavior_root_trap.gd`, `behavior_spitter.gd`, `behavior_spore.gd`
- Create : `game/scenes/hazards/hazard.gd` (base : signe au sol, puis impact), `thorn_projectile.tscn`, `vine_ring.tscn`, `spore_cloud.tscn`
- Create : `game/data/species/{croque_colere,lierre_jalousie,ortie_regret,champi_panique}.tres`, plus les 4 modèles dans `build_plants.py`
- Modify : `game/scenes/heroine/heroine.gd`, pour ajouter `immobilize(seconds)` et `slow(factor, seconds)` (on garde la plus longue durée, sans cumul)
- Test : `game/tests/unit/test_hostiles.gd`, `test_hazards.gd`

**Interfaces — Produces :**
- `PlantSpecies.minutes_reward()` : une hostile renvoie 40, et la capture n'est possible qu'endormie.
- `Hazard` (`extends Node3D`) : `telegraph_time >= 0.6`, signal `struck(target)`, `func setup(at: Vector3, telegraph: float) -> void`.
- `Heroine.immobilize(seconds: float) -> void` et `Heroine.slow(factor: float, seconds: float) -> void`.

- [ ] **Step 1 : tests.**
  - `test_hostile_capturable_only_asleep` *(Review Focus 1)* : un coup de filet sur une hostile réveillée échoue. Endormie : capture et +40 min. Si elle se réveille dans la même frame avant le coup, la capture échoue.
  - `test_charger_telegraphs_then_charges`.
  - `test_vine_ring_immobilizes_once_per_window`.
  - `test_spitter_shadow_precedes_impact` : le signe au sol arrive au moins 0,6 s avant l'impact.
  - `test_spore_slows_no_petal`.
  - `test_stacked_hazards_one_petal_and_no_cc_stacking` *(Review Focus 2)*.
  - `test_ronce_still_works` : non-régression.
- [ ] **Step 2 :** lance les tests. Attendu : FAIL.
- [ ] **Step 3 :** implémente. Rendus réels des 4 modèles et d'une attaque de chaque dans `scratchpad/preview/plants_b3/`.
- [ ] **Step 4 :** suite complète verte.
- [ ] **Step 5 :** commits par sous-sujet : base de danger, chaque hostile, capture endormie.

### Task B4 : Herbier à 12 pages et intégration finale

**Files :**
- Modify : `game/data/catalog.tres` (les 12 espèces, avec fragment et 2 détails chacune, textes « (provisoire) » en français), `game/scenes/ui/herbarium.gd`/`.tscn` (12 pages, défilement clavier et manette de la page d'espèce : finding mineur de la Tâche 13), `game/scripts/core/herbarium.gd`/`game/scripts/autoload/game_state.gd` si besoin
- Test : `game/tests/unit/test_bestiary_herbarium.gd`

- [ ] **Step 1 : tests.**
  - `test_catalog_has_12_species` : 7 non hostiles et 5 hostiles, chacune avec un modèle et des textes.
  - `test_old_save_loads_with_new_catalog` *(Review Focus 5)* : un JSON v1 avec 4 espèces se charge, 4 pages sont découvertes et 8 inconnues.
  - `test_harpoon_milestone_counts_captured_hostiles` : 3 espèces capturées, dont une hostile endormie → le harpon est débloqué.
  - `test_herbarium_page_scrolls_with_keyboard`.
- [ ] **Step 2 :** lance les tests. Attendu : FAIL.
- [ ] **Step 3 :** implémente. Rendu de l'herbier et d'une nuit à 5 h avec plusieurs espèces visibles, dans `scratchpad/preview/plants_b4/`.
- [ ] **Step 4 :** suite complète verte.
- [ ] **Step 5 :** commit `Expand the herbarium to the twelve-species bestiary`.
