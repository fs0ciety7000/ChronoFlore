# Deuxième héros, choix du personnage et coop locale — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** jouer la nuit seul avec l'héroïne ou le héros, ou à deux en coop locale sur la même île.

**Architecture :**
- Un seul script joueur (`Heroine`) instancié une ou deux fois, avec un `player_index` (actions d'entrée et appareil) et une scène visuelle (héroïne v2 ou héros).
- `NightSession` gère une liste de joueurs, et tout l'état de la nuit est partagé : horloge, lucidité, herbier.
- La caméra cadre le barycentre des joueurs.

**Tech Stack :** Godot 4.7.2, GDScript typé, modèles GLB faits maison (Blender/bpy).

**Spec :** `docs/superpowers/specs/2026-10-29-deuxieme-heros-coop-design.md` (validée). Elle complète `docs/superpowers/specs/2026-10-29-tranche-verticale-design.md`.

**Prérequis :**
- la passe visuelle (Tâche V) est terminée ;
- l'héroïne v2 est intégrée (Tâche H, phase 2) ;
- les rendus du héros sont validés par l'utilisateur (Tâche H2, phase 1).

## Global Constraints

- Les contraintes globales du plan `2026-10-29-tranche-verticale.md` s'appliquent toutes : GDScript typé, Compatibility, assets Polyfork ou faits maison, commande de test, trailers de commit, ne pas toucher `site/` ni `branding/`.
- Seule l'héroïne rêve. Les textes de fin et le HUD parlent d'elle, quel que soit le personnage joué.
- En coop :
  - J1 = héroïne, J2 = héros ;
  - pétales, horloge, herbier et outils débloqués sont partagés ;
  - chaque joueur a sa propre invulnérabilité de 1,5 s, ses outils et ses recharges ;
  - population capturable ×1,3 (arrondie) et +1 Ronce ;
  - laisse à 14 m.
- Assignation des entrées :
  - 2 manettes → manette 0 pour J1, manette 1 pour J2 ;
  - 1 manette → clavier-souris pour J1, manette 0 pour J2 ;
  - 0 manette → clavier partagé : J1 en ZQSD/WASD + F (outil) + R (outil suivant), J2 en flèches + Entrée / 0 du pavé (outil) + Point / point du pavé (outil suivant), jamais de touche modificatrice (Ctrl+W ferme l'onglet sur le Web). Visée en mode AUTO pour les deux.
- La caméra cadre le barycentre des joueurs. Sa taille ortho va de la taille solo (Tâche V) jusqu'à ×1,5 au maximum, selon l'écart entre les joueurs.

## Review Focus

1. **Manette débranchée en pleine coop** : le joueur concerné doit continuer à jouer au clavier, ou sa visée passe en AUTO. Sa visée ne doit jamais rester figée. *Tâche C3.*
2. **Les deux joueurs touchés par des Ronces dans la même frame** : chacun perd au plus un pétale sur sa propre fenêtre d'invulnérabilité, soit deux pétales au maximum, jamais plus. *Tâche C3.*
3. **Une plante attrapée au filet par les deux joueurs dans la même frame** : une seule capture, un seul ajout de minutes. *Tâche C3.*
4. **Un joueur qui sort du cadre** : la laisse le retient et la caméra garde les deux joueurs visibles. *Tâche C3.*
5. **Choix du mode, puis retour au titre, puis nouvelle nuit** : le mode est bien réinitialisé ou conservé comme affiché. *Tâche C2.*

---

### Task C1 : Intégrer le modèle du héros

**Files :**
- Create : `game/assets/custom/hero2/build_hero2.py` + `hero2.glb` (copiés depuis `scratchpad/hero2/` une fois validés)
- Create : `game/scenes/heroine/hero2_visual.tscn`
- Test : `game/tests/unit/test_hero2_visual.gd`

**Interfaces :**
- Consumes : l'interface du visuel de l'héroïne v2, telle qu'intégrée en Tâche H phase 2 (lecture des animations Idle/Walk/Swing/Hurt, `play_walk(speed)`, `play_swing()`, `play_hurt()` ; noms exacts à reprendre de `heroine_visual.gd` après la Tâche H).
- Produces : `hero2_visual.tscn`, une scène de même interface, interchangeable avec `heroine_visual.tscn`.

- [ ] **Step 1 :** test `test_hero2_visual_instantiates` : la scène s'instancie, son `AnimationPlayer` contient `Idle`, `Walk`, `Swing` et `Hurt`, `Idle` et `Walk` bouclent, et elle expose les mêmes méthodes que le visuel de l'héroïne.
- [ ] **Step 2 :** lance le test. Attendu : FAIL.
- [ ] **Step 3 :** copie le générateur et le GLB, puis crée la scène en réutilisant le script visuel de l'héroïne, paramétré par le GLB.
- [ ] **Step 4 :** lance le test. Attendu : PASS. Fais aussi un rendu Godot réel en jeu (xvfb) pour vérifier le cadrage.
- [ ] **Step 5 :** commit `Add hand-made second hero model`.

### Task C2 : Écran de choix et mode solo avec le héros

**Files :**
- Create : `game/scenes/ui/character_select.tscn` + `character_select.gd`
- Modify : `game/scripts/autoload/game_state.gd`, `game/scenes/ui/title.gd`, `game/scenes/heroine/heroine.gd`, `game/scenes/night/night_session.gd`
- Test : `game/tests/unit/test_character_select.gd`

**Interfaces — Produces :**
- `GameState`, ajouts :
  ```
  enum Mode { SOLO_HEROINE, SOLO_HERO, COOP }
  var mode: Mode = Mode.SOLO_HEROINE
  func start_night_with(p_mode: Mode) -> void
  ```
  `start_night()` reste un raccourci : il lance la nuit avec le mode courant.
- `Heroine`, ajouts :
  ```
  @export var player_index: int = 0
  @export var visual_scene: PackedScene
  ```
  Les actions d'entrée sont préfixées : `p1_*` pour l'index 0, `p2_*` pour l'index 1.
- `NightSession`, ajouts : `var players: Array[Heroine]` (une entrée en solo) et `func setup_players(mode: GameState.Mode) -> void`.

Règles :
- **Écran de choix** : trois cartes (« Elle », « Lui », « À deux »), chacune avec le rendu 3D du modèle en vignette (SubViewport) ou une capture figée. Il se navigue au clavier et à la manette.
- **Titre** : « Commencer la nuit » ouvre l'écran de choix.
- **InputMap** : renomme les actions existantes en `p1_*` et ajoute les `p2_*` (valeurs dans les Global Constraints). Mets à jour toutes les références existantes.

- [ ] **Step 1 : tests.**
  - `test_select_sets_mode` : choisir « Lui » donne `GameState.mode == SOLO_HERO`.
  - `test_solo_hero_spawns_hero_visual` : session en `SOLO_HERO` → un seul joueur, dont le visuel est `hero2_visual`.
  - `test_solo_heroine_default` : session par défaut → un seul joueur, l'héroïne.
  - `test_mode_persists_after_title` *(Review Focus 5)*.
  - `test_input_actions_prefixed` : chaque action `p1_*` et `p2_*` existe et a au moins un événement.
- [ ] **Step 2 :** lance les tests. Attendu : FAIL.
- [ ] **Step 3 :** implémente. Tous les tests existants doivent rester verts après le renommage `p1_*`.
- [ ] **Step 4 :** lance les tests. Attendu : PASS. Fais un rendu de l'écran de choix.
- [ ] **Step 5 :** commit `Add character select and solo hero mode`.

### Task C3 : Coop locale

**Files :**
- Create : `game/scripts/core/coop_rules.gd`, `game/scripts/core/device_assignment.gd`
- Modify : `game/scenes/night/night_session.gd`, `game/scenes/camera/iso_camera.gd`, `game/scenes/plants/plant.gd` (cible = joueur le plus proche), `game/scenes/ui/hud.gd` (une cartouche d'outil par joueur)
- Test : `game/tests/unit/test_coop_rules.gd`, `test_device_assignment.gd`, `test_coop_session.gd`

**Interfaces — Produces :**

`class_name CoopRules extends RefCounted` (méthodes statiques)
```
const POPULATION_FACTOR := 1.3
const EXTRA_NIGHTMARES := 1
const LEASH_DISTANCE := 14.0
const CAMERA_MAX_SCALE := 1.5
static func population(base: int, coop: bool) -> int    # roundi(base * 1.3) in coop
static func nightmares(base: int, coop: bool) -> int    # base + 1 in coop
static func camera_size(solo_size: float, spread: float) -> float  # solo_size .. solo_size*1.5, linear on spread 0..LEASH_DISTANCE
static func leash(pos: Vector2, other: Vector2) -> Vector2  # clamps pos to within LEASH_DISTANCE of other
static func nearest(point: Vector2, players: PackedVector2Array) -> int
```

`class_name DeviceAssignment extends RefCounted` (méthodes statiques)
```
enum Kind { KEYBOARD_MOUSE, KEYBOARD_LEFT, KEYBOARD_RIGHT, PAD }
static func assign(pad_ids: Array[int], coop: bool) -> Array[Dictionary]  # one {"kind": Kind, "device": int} per player, per Global Constraints
```

Règles :
- **Entrées** : la session réapplique l'assignation à chaque `Input.joy_connection_changed`. En coop, une manette débranchée fait passer son joueur sur sa moitié de clavier, avec la visée en AUTO.
- **Plantes** : `set_threat` reçoit la position et la visée du joueur le plus proche. Une Ronce cible le joueur le plus proche, et son contact appelle `take_nightmare_hit()` sur ce joueur.
- **Lucidité** : `Lucidity` reste unique, et chaque joueur garde sa fenêtre d'invulnérabilité. Remplace `Lucidity.take_hit(time)` par `take_hit_for(player_index: int, time: float) -> bool`, en gardant `take_hit(time)` comme alias de l'index 0.
- **Captures** : la capture est idempotente (une plante déjà CAPTURED renvoie false), ce qui empêche une double capture.
- **Apparition** : les plantes apparaissent à la distance minimale de chaque joueur.

- [ ] **Step 1 : tests.**
  - `CoopRules` : tous les cas, dont `population(6, true) == 8`, `camera_size(12, 0) == 12`, `camera_size(12, 14) == 18`, `leash`, `nearest`.
  - `DeviceAssignment` : 0, 1 et 2 manettes, en solo et en coop.
  - Session :
    - `test_shared_lucidity_two_hits` *(Review Focus 2)* : deux coups dans la même frame, un sur chaque joueur → 2 pétales perdus. Deux coups sur le même joueur → 1 pétale.
    - `test_double_net_single_capture` *(Review Focus 3)*.
    - `test_pad_unplug_falls_back` *(Review Focus 1)*.
    - `test_leash_and_camera_frame_both` *(Review Focus 4)*.
    - `test_coop_population` : population et Ronces en coop.
- [ ] **Step 2 :** lance les tests. Attendu : FAIL.
- [ ] **Step 3 :** implémente.
- [ ] **Step 4 :** lance les tests. Attendu : PASS. Fais un rendu de la coop à 0 h et à 4 h avec les deux personnages.
- [ ] **Step 5 :** commit `Add local co-op night`.
