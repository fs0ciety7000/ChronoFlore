# Tranche verticale ChronoFlore — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** une nuit jouable de bout en bout sur une île en diorama. La rêveuse ralentit et capture des plantes-émotions qui fuient, chaque capture fait avancer l'heure, et la lucidité (pétales) peut la réveiller trop tôt. L'herbier persiste entre les nuits et débloque le harpon.

**Architecture :**
- **Règles pures :** horloge, lucidité, torpeur, herbier, sauvegarde, apparition, géométrie de l'île, palette, visée, pilotage. Ce sont des classes `RefCounted` sans nœud, testées en headless.
- **Contenu :** espèces, outils, paliers et souvenirs d'aube sont des `Resource` en `.tres` réunis dans un catalogue.
- **Scènes :** des scènes Godot minces (héroïne, plante, outils, nuit, UI) branchent ces règles par signaux, et un autoload `GameState` porte l'herbier entre les scènes.

**Tech Stack :** Godot 4.7.2, GDScript typé, 3D, `Camera3D` orthographique, renderer Compatibility, export Web.

**Spec :** `docs/superpowers/specs/2026-10-29-tranche-verticale-design.md` (validée). Lis-la avant chaque tâche : ce plan cite ses sections (§).

## Global Constraints

- Godot 4.7.2, GDScript **typé statiquement** (types sur variables, paramètres, retours). Code et commentaires en anglais, textes affichés en français.
- Renderer `gl_compatibility` partout, et l'export Web sans threads (preset existant). N'utilise ni compute shader, ni SDFGI, ni rien qui casse Compatibility.
- 3D, `Camera3D` en `PROJECTION_ORTHOGONAL`, angle iso fixe : pitch −35,264°, yaw 45°.
- Assets 3D : uniquement Polyfork (GLB dans `game/assets/polyfork/<asset-id>/<asset-id>.glb`) ou des primitives et modèles faits maison (`game/assets/custom/`). Pas de rescale pour tricher sur la taille.
- **Les GLB Polyfork s'importent avec leurs couleurs de sommets, mais avec `vertex_color_use_as_albedo = false`** (vérifié sur `steampunk-farm-terrain-98cb8a`). Sans correction, ils s'affichent blancs. Passe tout GLB Polyfork par `PolyforkUtil.enable_vertex_colors()` (Tâche 7).
- **`class_name` exige le cache d'import :** dans un clone neuf, ou après avoir ajouté un `class_name`, lance `godot --headless --path game --import` avant les tests. Sinon : `Identifier "X" not declared` (vérifié).
- Commande de test (doit sortir 0) : `godot --headless --path game --import && godot --headless --path game --script res://tests/test_runner.gd`. Sortie attendue en fin de ligne : `Results: N passed, 0 failed`.
- Chiffres de départ (§5, à régler en jeu, centralisés en constantes ou en `.tres`, jamais en dur dans plusieurs fichiers) :
  - nuit de 480 min ; récompenses commune 20, peu commune 40, rare 60 ;
  - 5 pétales, repousse après 3 captures sans perte, invulnérabilité 1,5 s après un coup ;
  - torpeur −25 %/charge, sommeil à 3 charges pendant 3 s, retombée d'une charge toutes les 2,5 s ; harpon : cloue 3 s, recharge 2,5 s ;
  - filet : portée 2 m, capture à ≥ 2 charges, endormie, clouée ou Timidelle émergente ;
  - vitesse des plantes +8 % par heure ; peu communes à partir de 2 h, rares à partir de 4 h ; 1 à 3 cauchemars ; 6 à 8 plantes en jeu ;
  - harpon débloqué à 3 espèces capturables découvertes ; détails de page à 5 et 15 ; 3 souvenirs d'aube.
- Pas de contrôles tactiles dans cette tranche. Mais aucune règle de gameplay ne lit la souris directement : tout passe par une direction de visée fournie (§6).
- Ne touche ni à `site/` ni à `branding/`. Petits commits, un sujet par commit, jamais de `--force`. Pousse sur `claude/chronoflore-game`.
- Commits avec les trailers :
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01NEYy5PAbarRz7XAx6sA84G
  ```

## Review Focus

Ces cas peuvent mordre un joueur sans que la spec les nomme. Chacun a son test dans la tâche indiquée.

1. **Sauvegarde corrompue, absente ou d'une version inconnue** (navigateur nettoyé, ancienne build) → on repart d'un herbier neuf, sans crash et sans écraser silencieusement un fichier lisible. *Tâche 5.*
2. **Deux coups de Ronce dans la même frame** (deux ronces au contact) → un seul pétale perdu grâce à l'invulnérabilité. Les fuites de plantes, elles, ignorent l'invulnérabilité. *Tâche 2.*
3. **Plusieurs captures qui dépassent 8 h** (capture rare à 7 h 40) → l'horloge plafonne à 480 et `dawn_reached` n'est émis qu'une fois. *Tâche 1.*
4. **Plante poussée au bord sans être paniquée** (ralentie, endormie ou Ronce) → elle ne tombe jamais : seule une plante en panique peut s'échapper. *Tâche 8.*
5. **Passage souris ↔ manette en pleine nuit, ou manette débranchée** → la source de visée suit le dernier périphérique utilisé, sans visée figée. *Tâche 10.*

---

### Task 0 : Harnais de tests modulaire

**Files :**
- Create : `game/tests/test_case.gd`
- Modify : `game/tests/test_runner.gd`
- Create : `game/tests/unit/test_sanity.gd` (reprend `test_sanity` existant)

**Interfaces :**
- Produces : la classe de base `res://tests/test_case.gd` (`extends RefCounted`) avec les méthodes suivantes.
  ```
  assert_eq(actual, expected, label: String) -> void
  assert_true(cond: bool, label: String) -> void
  assert_false(cond: bool, label: String) -> void
  assert_near(actual: float, expected: float, eps: float, label: String) -> void
  ```
  Elle porte aussi les compteurs `passed: int` et `failed: int`. Chaque fichier `tests/unit/test_*.gd` hérite (`extends "res://tests/test_case.gd"`) et expose des méthodes `test_*()` sans argument.
- Le runner charge chaque `res://tests/unit/test_*.gd` (via `DirAccess`, en ordre alphabétique), instancie le script, appelle chaque méthode dont le nom commence par `test_`, cumule les compteurs, affiche `Results: %d passed, %d failed` et `quit(1)` en cas d'échec. Un échec affiche `FAIL <fichier>::<méthode> <label>: expected X, got Y` via `push_error`.

- [ ] **Step 1 :** écris `test_case.gd` et `tests/unit/test_sanity.gd`, avec `test_project_name()` qui vérifie que `application/config/name` vaut `"ChronoFlore"`, puis réécris le runner.
- [ ] **Step 2 :** ajoute temporairement un `assert_eq(1, 2, "deliberate")`, lance la commande de test et vérifie la sortie `Results: 1 passed, 1 failed` avec le code de sortie 1. Retire l'assert.
- [ ] **Step 3 :** lance la commande de test. Attendu : `Results: 1 passed, 0 failed`, code de sortie 0.
- [ ] **Step 4 :** dans `AGENTS.md` § Commandes, change la ligne `test:` en `godot --headless --path game --import && godot --headless --path game --script res://tests/test_runner.gd`. Commit : `Split headless tests into per-file test cases`.

### Task 1 : NightClock

**Files :** Create `game/scripts/core/night_clock.gd` · Test `game/tests/unit/test_night_clock.gd`

**Interfaces — Produces :** `class_name NightClock extends RefCounted`
```
const NIGHT_MINUTES := 480
signal dawn_reached
signal minutes_changed(minutes: int)
var minutes: int  # 0..480
func add_minutes(amount: int) -> void   # clamps to 480; emits minutes_changed when the value changes; emits dawn_reached once, when reaching 480
func progress() -> float                # minutes / 480.0
func hour() -> float                    # minutes / 60.0
func is_dawn() -> bool
```

- [ ] **Step 1 : tests.**
  - `test_starts_at_zero` : progress 0, non dawn.
  - `test_add_minutes` : +20 → minutes 20, hour ≈ 0,333.
  - `test_clamps_and_dawn_once` : minutes à 460, puis +60 → minutes 480, is_dawn true. Un +20 supplémentaire laisse minutes à 480. Un compteur connecté à `dawn_reached` vaut 1.
  - `test_progress_half` : 240 → 0,5.
  - `test_minutes_changed` : `add_minutes(20)` émet `minutes_changed(20)` ; à 480, un `add_minutes(20)` n'émet rien.
- [ ] **Step 2 :** lance les tests. Attendu : FAIL, `NightClock` non déclaré.
- [ ] **Step 3 :** implémente.
- [ ] **Step 4 :** lance import + tests. Attendu : 0 failed.
- [ ] **Step 5 :** commit `Add NightClock core rule`.

### Task 2 : Lucidity

**Files :** Create `game/scripts/core/lucidity.gd` · Test `game/tests/unit/test_lucidity.gd`

**Interfaces — Produces :** `class_name Lucidity extends RefCounted`
```
const STREAK_FOR_REGROW := 3
const HIT_INVULNERABILITY := 1.5
signal petal_lost(petals_left: int)
signal petal_regrown(petals: int)
signal depleted
var max_petals: int
var petals: int
var streak: int
func _init(p_max_petals: int = 5) -> void
func lose_petal() -> void                 # escapes: ignores invulnerability; resets streak; emits depleted when reaching 0
func take_hit(time_s: float) -> bool      # nightmare contact: false if within 1.5 s of last accepted hit
func register_capture() -> void           # streak += 1; at 3: regrow one petal if below max, streak = 0
func is_empty() -> bool
```

- [ ] **Step 1 : tests.**
  - `test_starts_full` : 5.
  - `test_lose_and_deplete` : 5 fois `lose_petal` → 0, `depleted` émis une fois, un 6e appel reste à 0.
  - `test_regrow_after_three_captures` : 4 pétales, puis 3 captures → 5, streak 0.
  - `test_loss_resets_streak` : 2 captures, une perte, 2 captures → pas de repousse.
  - `test_no_regrow_above_max` : 5 pétales, 3 captures → reste 5.
  - `test_hit_invulnerability` *(Review Focus 2)* :
    - `take_hit(10.0)` → true ;
    - `take_hit(10.0)` → false ;
    - `take_hit(11.4)` → false ;
    - `take_hit(11.6)` → true ;
    - petals = 3.
  - `test_escape_ignores_invulnerability` : `take_hit(0)` puis `lose_petal()` → 3.
- [ ] **Step 2 :** lance les tests. Attendu : FAIL.
- [ ] **Step 3 :** implémente.
- [ ] **Step 4 :** lance les tests. Attendu : PASS.
- [ ] **Step 5 :** commit `Add Lucidity core rule`.

### Task 3 : Torpor (état d'une plante face aux outils)

**Files :** Create `game/scripts/core/torpor.gd` · Test `game/tests/unit/test_torpor.gd`

**Interfaces — Produces :** `class_name Torpor extends RefCounted`
```
const SLOW_PER_CHARGE := 0.25
const SLEEP_CHARGES := 3
const SLEEP_DURATION := 3.0
const DECAY_INTERVAL := 2.5
const PIN_DURATION := 3.0
const NET_MIN_CHARGES := 2
signal fell_asleep
var charges: int
func add_dart() -> void          # +1 charge, restarts decay timer; at 3 → asleep 3 s, charges = 0, emits fell_asleep
func pin() -> void               # pinned 3 s (refreshes)
func tick(delta: float) -> void  # counts down sleep/pin; one charge decays per 2.5 s without a dart
func is_asleep() -> bool
func is_pinned() -> bool
func speed_factor() -> float     # 0.0 if asleep or pinned, else 1.0 - 0.25 * charges
func net_can_capture(emerging: bool) -> bool  # asleep or pinned or charges >= 2 or emerging
```

- [ ] **Step 1 : tests.**
  - `test_darts_slow` : 1 fléchette → 0,75 ; 2 → 0,5.
  - `test_three_darts_sleep` : 3 fléchettes → asleep, speed 0, `fell_asleep` émis. Après `tick(3.1)` → awake, charges 0, speed 1,0.
  - `test_decay` : 2 fléchettes, `tick(2.6)` → 1 charge, `tick(2.6)` → 0.
  - `test_dart_restarts_decay` : 1 fléchette, `tick(2.0)`, 1 fléchette, `tick(2.0)` → toujours 2 charges.
  - `test_pin` : `pin()` → pinned, speed 0. `tick(3.1)` → libre.
  - `test_net_rules` :
    - 0 charge → false ;
    - 1 charge → false ;
    - 2 charges → true ;
    - endormie → true ;
    - clouée → true ;
    - `net_can_capture(true)` sans charge → true.
- [ ] **Step 2 :** lance les tests. Attendu : FAIL.
- [ ] **Step 3 :** implémente.
- [ ] **Step 4 :** lance les tests. Attendu : PASS.
- [ ] **Step 5 :** commit `Add Torpor capture rules`.

### Task 4 : Ressources de contenu et catalogue

**Files :**
- Create : `game/scripts/data/plant_species.gd`, `tool_data.gd`, `unlock_milestone.gd`, `game_catalog.gd`
- Create : `game/data/species/revette.tres`, `nostalgerbe.tres`, `timidelle.tres`, `ronce_angoisse.tres`
- Create : `game/data/tools/net.tres`, `tranquilizer.tres`, `harpoon.tres`
- Create : `game/data/milestones/harpoon_at_3.tres`, `game/data/catalog.tres`
- Test : `game/tests/unit/test_catalog.gd`

**Interfaces — Produces :**

`class_name PlantSpecies extends Resource`
```
enum Rarity { COMMON, UNCOMMON, RARE }
enum Behavior { DARTER, ZIGZAG, BURROWER, STALKER }
@export var id: StringName
@export var display_name: String
@export var emotion: String
@export var rarity: Rarity
@export var capturable: bool = true
@export var base_speed: float      # m/s
@export var min_hour: float
@export var behavior: Behavior
@export var panic_after: float = 8.0   # seconds alerted before panicking (Task 8)
@export var visual_scene: PackedScene  # may be null until Task 12
@export_multiline var fragment: String
@export var details: PackedStringArray # exactly 2
func minutes_reward() -> int           # COMMON 20, UNCOMMON 40, RARE 60; 0 if not capturable
```

`class_name ToolData extends Resource`
```
enum Effect { TORPOR, PIN, CAPTURE }
@export var id: StringName
@export var display_name: String
@export var effect: Effect
@export var cooldown: float
@export var max_range: float
@export var projectile_speed: float   # 0 for net
@export var unlocked_by_default: bool
```

`class_name UnlockMilestone extends Resource`
```
@export var capturable_species_required: int
@export var reward_tool_id: StringName
```

`class_name GameCatalog extends Resource`
```
@export var species: Array[PlantSpecies]
@export var tools: Array[ToolData]
@export var milestones: Array[UnlockMilestone]
@export var dawn_memories: PackedStringArray  # 3, ordered
func species_by_id(id: StringName) -> PlantSpecies
func tool_by_id(id: StringName) -> ToolData
```

**Valeurs exactes :**

| id | display_name | emotion | rarity | capturable | base_speed | min_hour | behavior |
|---|---|---|---|---|---|---|---|
| `revette` | Rêvette | joie légère | COMMON | oui | 4.5 | 0 | DARTER |
| `nostalgerbe` | Nostalgerbe | nostalgie | COMMON | oui | 3.5 | 0 | ZIGZAG |
| `timidelle` | Timidelle | timidité | UNCOMMON | oui | 3.0 | 2 | BURROWER |
| `ronce_angoisse` | Ronce-Angoisse | angoisse | COMMON | non | 1.2 | 0 | STALKER |

Les fragments, les détails et les 3 souvenirs d'aube sont écrits en français. Chacun est un texte provisoire de 2 à 3 phrases (1 phrase pour un détail), mélancolique et kawaï, préfixé `(provisoire) `.

| id | effect | cooldown | max_range | projectile_speed | unlocked_by_default |
|---|---|---|---|---|---|
| `net` (Filet) | CAPTURE | 0.5 | 2.0 | 0 | oui |
| `tranquilizer` (Fusil tranquillisant) | TORPOR | 0.6 | 14.0 | 18.0 | oui |
| `harpoon` (Harpon) | PIN | 2.5 | 10.0 | 12.0 | non |

Palier : `capturable_species_required = 3`, `reward_tool_id = &"harpoon"`.

- [ ] **Step 1 : tests.**
  - `test_catalog_loads` : `load("res://data/catalog.tres")` contient 4 espèces, 3 outils, 1 palier et 3 souvenirs d'aube.
  - `test_species_values` : vérifie le tableau ci-dessus et `minutes_reward()` (revette 20, timidelle 40, ronce 0).
  - `test_each_species_has_texts` : fragment non vide, `details.size() == 2`.
  - `test_lookup` : `species_by_id(&"timidelle").display_name == "Timidelle"`, `tool_by_id(&"nope") == null`.
- [ ] **Step 2 :** lance les tests. Attendu : FAIL.
- [ ] **Step 3 :** écris les scripts et les `.tres`. Les `.tres` sont du texte : référence les scripts par `ext_resource` et laisse `visual_scene` vide pour l'instant.
- [ ] **Step 4 :** lance import + tests. Attendu : PASS.
- [ ] **Step 5 :** commit `Add data-driven species, tools and catalog`.

### Task 5 : Herbarium et SaveStore

**Files :**
- Create : `game/scripts/core/herbarium.gd`, `game/scripts/core/save_store.gd`
- Test : `game/tests/unit/test_herbarium.gd`, `game/tests/unit/test_save_store.gd`

**Interfaces — Produces :**

`class_name Herbarium extends RefCounted`
```
const SAVE_VERSION := 1
const DETAIL_THRESHOLDS := [5, 15]
var counts: Dictionary              # StringName -> int (captures, or sleeps for non-capturable)
var unlocked_tools: Array[StringName]
var best_minutes: int
var full_nights: int
var next_dawn_memory: int
func record(species: PlantSpecies) -> Dictionary  # {"new_species": bool, "new_detail": int}; new_detail = 0 or 1 when a threshold is crossed, else -1
func is_discovered(id: StringName) -> bool
func revealed_details(id: StringName) -> int      # 0..2
func discovered_capturable_count(catalog: GameCatalog) -> int
func apply_milestones(catalog: GameCatalog) -> Array[StringName]  # newly unlocked tool ids
func available_tools(catalog: GameCatalog) -> Array[StringName]  # defaults + unlocked, catalog order
func register_night(minutes: int, full: bool, catalog: GameCatalog) -> int  # updates best/full_nights; on full night returns the revealed dawn memory index (then increments), else -1; -1 once all are read
func to_dict() -> Dictionary
static func from_dict(d: Dictionary) -> Herbarium  # returns null if version != 1 or shape invalid
```

`class_name SaveStore extends RefCounted`
```
const DEFAULT_PATH := "user://save.json"
static func save(h: Herbarium, path: String = DEFAULT_PATH) -> Error
static func load_or_new(path: String = DEFAULT_PATH) -> Herbarium  # missing/unparsable/invalid → Herbarium.new(); an unreadable existing file is copied to path + ".bak" before returning new
```

- [ ] **Step 1 : tests.**
  - `test_record_new_species` : le premier `record(revette)` renvoie `{"new_species": true, "new_detail": -1}` ; ensuite `is_discovered` est vrai.
  - `test_detail_thresholds` : la 5e capture renvoie `new_detail == 0` et la 15e `new_detail == 1`. `revealed_details` vaut 0 après 4 captures, 1 après 5, 2 après 15.
  - `test_ronce_counts_but_not_toward_milestone` : record de revette, nostalgerbe et ronce. `discovered_capturable_count` vaut 2 et `apply_milestones` renvoie `[]`. Après un record de timidelle, elle renvoie `[&"harpoon"]`, et un second appel renvoie `[]`.
  - `test_available_tools` : neuf → `[&"net", &"tranquilizer"]` ; après déblocage → les 3.
  - `test_register_night` :
    - (300, false) → -1, best 300 ;
    - (480, true) → 0 ; puis 1, puis 2 ;
    - le 4e appel (480, true) → -1 ;
    - à la fin : full_nights 4, best 480.
  - `test_roundtrip` : `from_dict(to_dict())` conserve counts, outils, best, full_nights et next_dawn_memory.
  - `test_save_store_roundtrip` : écrit dans `user://test_save.json`, recharge, compare, puis supprime le fichier.
  - `test_save_store_missing` : un chemin inexistant donne un herbier neuf.
  - `test_save_store_corrupt` *(Review Focus 1)* : écrit `"{not json"` → herbier neuf et `.bak` présent. Écrit `{"version": 99}` → herbier neuf. Nettoie les fichiers.
- [ ] **Step 2 :** lance les tests. Attendu : FAIL.
- [ ] **Step 3 :** implémente avec `JSON.stringify` / `JSON.parse_string`. Convertis les clés `StringName` ↔ `String` dans `to_dict`/`from_dict`.
- [ ] **Step 4 :** lance les tests. Attendu : PASS.
- [ ] **Step 5 :** commit `Add persistent herbarium and save store`.

### Task 6 : SpawnRules, IslandShape, NightPalette

**Files :**
- Create : `game/scripts/core/spawn_rules.gd`, `island_shape.gd`, `night_palette.gd`
- Test : `game/tests/unit/test_spawn_rules.gd`, `test_island_shape.gd`, `test_night_palette.gd`

**Interfaces — Produces :**

`class_name SpawnRules extends RefCounted` (méthodes statiques)
```
const RARITY_WEIGHTS := { PlantSpecies.Rarity.COMMON: 6, PlantSpecies.Rarity.UNCOMMON: 3, PlantSpecies.Rarity.RARE: 1 }
static func eligible_capturables(catalog: GameCatalog, hour: float) -> Array[PlantSpecies]  # capturable and min_hour <= hour
static func target_population(hour: float) -> int   # mini(6 + int(hour / 3.0), 8)
static func nightmare_count(hour: float) -> int     # mini(1 + int(hour / 3.0), 3)
static func speed_multiplier(hour: float) -> float  # 1.0 + 0.08 * hour
static func pick(eligible: Array[PlantSpecies], rng: RandomNumberGenerator) -> PlantSpecies  # weighted by RARITY_WEIGHTS
```

`class_name IslandShape extends Resource` (contour XZ en mètres, sens quelconque)
```
@export var outline: PackedVector2Array
func contains(p: Vector2) -> bool
func distance_to_edge(p: Vector2) -> float      # >= 0, distance to nearest outline segment
func outward_normal(p: Vector2) -> Vector2       # unit vector from nearest edge point away from interior
func clamp_inside(p: Vector2, margin: float) -> Vector2  # p if inside with >= margin; else nearest point at margin inside
func random_point(rng: RandomNumberGenerator, margin: float) -> Vector2
func centroid() -> Vector2
```

`class_name NightPalette extends RefCounted`
```
static func sample(progress: float) -> Dictionary
# keys: "background": Color, "sun_color": Color, "sun_energy": float, "ambient_color": Color, "sun_pitch_deg": float, "plant_glow": float
```

Points clés (interpolation linéaire entre eux ; progress est borné à [0, 1]) :

| progress (h) | background | sun_color | sun_energy | ambient_color | sun_pitch_deg | plant_glow |
|---|---|---|---|---|---|---|
| 0.0 (0 h) | `#f6efe0` | `#fff4e0` | 1.0 | `#fdf6ea` | -55 | 0.0 |
| 0.25 (2 h) | `#f6efe0` | `#ffe9cc` | 0.95 | `#f7efe6` | -40 | 0.0 |
| 0.375 (3 h) | `#2e2f63` | `#8d8fd8` | 0.45 | `#5a5c9e` | -60 | 1.0 |
| 0.75 (6 h) | `#2e2f63` | `#8d8fd8` | 0.45 | `#5a5c9e` | -60 | 1.0 |
| 1.0 (8 h) | `#f7c9d4` | `#ffd1dc` | 0.8 | `#f0d4e8` | -20 | 0.3 |

- [ ] **Step 1 : tests.**
  - spawn :
    - à 0 h → revette et nostalgerbe ; à 2 h → les trois capturables ;
    - `target_population` : 6 à 0 h, 7 à 3 h, 8 à 7,9 h ;
    - `nightmare_count` : 1, 2, 3 à 0, 3 et 6 h ;
    - `speed_multiplier(5)` ≈ 1,4 ;
    - avec un RNG seed 1 et 600 tirages sur [revette, timidelle], revette est tirée entre 55 % et 80 % du temps.
  - île (carré 0..10) :
    - `contains(5,5)` vrai, `contains(11,5)` faux ;
    - `distance_to_edge(5,1)` ≈ 1 ;
    - `outward_normal(5,1)` ≈ (0,−1) ;
    - `clamp_inside((12,5), 0.5)` ≈ (9,5 ; 5) ;
    - `random_point` × 50 → tous `contains` avec distance ≥ marge ;
    - `centroid` ≈ (5,5).
  - palette :
    - `sample(0)["background"]` ≈ `#f6efe0` ;
    - `sample(0.5)["plant_glow"]` ≈ 1 ;
    - `sample(1.0)["background"]` ≈ `#f7c9d4` ;
    - `sample(-1)` équivaut à `sample(0)` et `sample(2)` à `sample(1)`.
- [ ] **Step 2 :** lance les tests. Attendu : FAIL.
- [ ] **Step 3 :** implémente avec `Geometry2D.is_point_in_polygon` et `Geometry2D.get_closest_point_to_segment`.
- [ ] **Step 4 :** lance les tests. Attendu : PASS.
- [ ] **Step 5 :** commit `Add spawn rules, island shape and night palette`.

### Task 7 : L'île (décor Polyfork) et la lumière de nuit

**Files :**
- Create : `game/scripts/util/polyfork_util.gd`, `game/scenes/island/island.tscn` + `island.gd`, `game/data/island_shape.tres`
- Create : `game/scenes/env/night_lighting.tscn` + `night_lighting.gd`
- Assets : `game/assets/polyfork/<id>/<id>.glb`
- Test : `game/tests/unit/test_island_scene.gd`

**Interfaces :**
- Produces : `class_name PolyforkUtil` avec `static func enable_vertex_colors(root: Node) -> void`. La fonction parcourt les `MeshInstance3D` et, pour chaque surface dont le matériau est un `BaseMaterial3D`, le duplique et y met `vertex_color_use_as_albedo = true`.
- Produces : `island.gd` (`class_name Island extends Node3D`) avec `@export var shape: IslandShape`, `func ground_height() -> float` (renvoie 0.0 ; la tranche joue sur un plateau plat à y = 0) et le groupe `"island"`.
- Produces : `night_lighting.gd` (`class_name NightLighting extends Node3D`). Elle contient `DirectionalLight3D` et `WorldEnvironment` et expose `@export var target_progress: float`. Dans `_process`, elle fait tendre sa progression affichée vers la cible (`lerp`, facteur `1.0 - exp(-1.5 * delta)`) et applique `NightPalette.sample()` : fond `BG_COLOR` = background, ambiant, couleur, énergie et pitch du soleil. Elle émet `glow_changed(value: float)` quand `plant_glow` change de plus de 0,01. Tone mapping **linéaire** (pas d'ACES : recommandation Polyfork). Ombres activées.

- [ ] **Step 1 :** télécharge `https://polyfork.dev/cdn/steampunk-farm-terrain-98cb8a.glb` dans `game/assets/polyfork/steampunk-farm-terrain-98cb8a/`. Les décors de plantes géantes viennent de `insect-world-e44b9f` : `common-daisy-6b2004`, `white-clover-plant-6ed185`, `puffball-mushroom-3b1324`, `glowing-bonnet-mushroom-13f518`, `moss-cushion-2eabef` (URL `https://polyfork.dev/cdn/<id>.glb`). Ajoute 2 ou 3 arbres de `nature-forest-kit-f29d6a` (consulte `get_kit` du MCP polyfork). Aucun bâtiment steampunk.
- [ ] **Step 2 :** le test `test_island_scene.gd`.
  - `test_island_instantiates` : `island.tscn` s'instancie, a une `shape` dont l'outline compte ≥ 8 points, et `shape.contains(Vector2.ZERO)`.
  - `test_vertex_colors_enabled` : après `_ready` (appelle `PolyforkUtil.enable_vertex_colors` sur l'instance, puis inspecte), au moins un `MeshInstance3D` a `vertex_color_use_as_albedo == true`.
  - `test_lighting_applies_palette` : instancie `night_lighting.tscn`, règle la progression affichée à 1.0 directement (`set_display_progress(1.0)`, une méthode publique à exposer pour les tests) et vérifie que la couleur de fond ≈ `#f7c9d4`.
- [ ] **Step 3 :** lance les tests. Attendu : FAIL.
- [ ] **Step 4 :** construis `island.tscn`.
  - Le terrain est placé à l'origine tel quel (son plateau herbeux est à y = 0 et il est à peu près centré : vérifié).
  - `StaticBody3D` sol : une `BoxShape3D` plate sous la zone jouable.
  - Décors : chaque décor gros a son `StaticBody3D` avec un cylindre approximatif.
  - Contour : `island_shape.tres` est un polygone de 12 à 16 points qui suit le plateau à environ 1 m du bord.
- [ ] **Step 5 :** lance les tests. Attendu : PASS.
- [ ] **Step 6 :** ouvre `godot --path game` avec une scène de test temporaire, ou fais une capture headless si l'environnement le permet. Vérifie de visu que le terrain est coloré et pas blanc. Sinon, note-le pour la vérification manuelle (Tâche 15).
- [ ] **Step 7 :** commit `Add Polyfork island and night lighting`.

### Task 8 : Steering et machine à états des plantes

**Files :**
- Create : `game/scripts/core/steering.gd`
- Create : `game/scenes/plants/plant.tscn` + `plant.gd`
- Create : `game/scripts/plants/plant_behavior.gd` (base) + `behavior_darter.gd`, `behavior_zigzag.gd`, `behavior_burrower.gd`, `behavior_stalker.gd`
- Create : `game/scenes/plants/visuals/revette.tscn`, `nostalgerbe.tscn`, `timidelle.tscn`, `ronce_angoisse.tscn` (primitives, §5.9). Mets à jour `visual_scene` dans les `.tres`.
- Test : `game/tests/unit/test_steering.gd`, `game/tests/unit/test_plant.gd`

**Interfaces — Produces :**

`class_name Steering extends RefCounted` (méthodes statiques, sur le plan XZ en `Vector2`)
```
const EDGE_AVOID_DISTANCE := 3.0
static func flee(plant: Vector2, threat: Vector2, island: IslandShape, panic: bool) -> Vector2  # unit; away from threat; when !panic and distance_to_edge < 3, blends toward inward so dot(result, outward_normal) <= 0; when panic, heads to nearest edge (outward_normal)
static func zigzag(dir: Vector2, phase_sign: int) -> Vector2   # dir rotated by ±35°
static func seek(from: Vector2, to: Vector2) -> Vector2
static func in_cone(origin: Vector2, dir: Vector2, target: Vector2, half_angle_deg: float, max_range: float) -> bool
```

`plant.gd`, `class_name Plant extends CharacterBody3D`, groupe `"plants"`
```
enum State { WANDER, ALERT, FLEE, PANIC, BURROWED, EMERGING, CAPTURED, ESCAPED }
signal captured(plant: Plant)
signal escaped(plant: Plant)
signal fell_asleep(plant: Plant)   # relays Torpor.fell_asleep (herbarium page for Ronce)
var species: PlantSpecies
var torpor: Torpor
var state: State
var speed_multiplier: float = 1.0
func setup(p_species: PlantSpecies, p_island: IslandShape, p_speed_multiplier: float) -> void
func set_threat(position_xz: Vector2, aim_dir: Vector2) -> void   # heroine position + aim each frame
func hit_by_tool(effect: ToolData.Effect) -> bool  # TORPOR→add_dart; PIN→pin; CAPTURE→try capture (net_can_capture(state == EMERGING) and species.capturable); returns true if captured; BURROWED ignores everything
func is_emerging() -> bool
```

Règles (§5.4 et choix de la spec) :
- **Alerte** à moins de 7 m de l'héroïne (WANDER → FLEE).
- **Panique et fuite :** après `species.panic_after` secondes en FLEE sans capture, la plante passe en PANIC. Elle file alors vers le bord le plus proche. Une plante PANIC hors du contour, ou à moins de 0,2 m du bord, saute : état ESCAPED, `escaped` émis, puis elle tombe et se libère après 1 s.
- **Retour au calme :** une plante qui a été loin de l'héroïne (> 12 m) pendant 4 s revient en WANDER et son compteur de panique repart à zéro.
- **Hors panique, une plante ne quitte jamais l'île :** `clamp_inside(margin 0.3)` à chaque frame. *(Review Focus 4)*
- **Vitesse effective** = `base_speed × speed_multiplier × torpor.speed_factor()`. `torpor.tick(delta)` est appelé chaque frame.
- **Comportements :**
  - DARTER : sprint 1,2 s puis pause 0,8 s pendant la fuite.
  - ZIGZAG : `zigzag()` dont le signe s'inverse toutes les 0,6 s. La plante se fige (vitesse 0) si elle n'est pas dans le cône de visée de l'héroïne (`in_cone`, demi-angle 45°, portée 30 m) et à au moins 4 m.
  - BURROWER : si l'héroïne est à moins de 4 m, elle passe en BURROWED (invisible, sans collision) pendant 1,2 s, puis réapparaît en EMERGING à 4–6 m dans la direction de fuite (bornée dans l'île) pendant 1,0 s, puis reprend FLEE.
  - STALKER : jamais d'alerte ni de fuite ; il fait `seek` vers l'héroïne. Contact (< 0,9 m) → appelle `heroine.take_nightmare_hit()` (groupe `"heroine"`).
- **Visuels :** rebond idle, tremblement en ALERT, affaissement endormi. Émission = `plant_glow` reçu par `set_glow(value: float)`.

- [ ] **Step 1 : tests de steering.**
  - `test_flee_center` : plante (5,5), menace (4,5), carré 0..20 → x > 0,9.
  - `test_flee_near_edge_stays_in` *(Review Focus 4)* : plante (0,5 ; 10), menace (3 ; 10), non panique → `dot(result, outward_normal) <= 0`.
  - `test_flee_panic_goes_out` : même cas en panique → `dot > 0,5`.
  - `test_zigzag_angle` : angle ≈ ±35°.
  - `test_in_cone` : cible devant à 5 m → vrai ; derrière → faux.
- [ ] **Step 2 : tests de plante** (`plant.tscn` instancié dans un `Node3D` racine ajouté à `root`, avec une `IslandShape` carrée 0..20).
  - `test_net_fails_on_fresh_plant` : `hit_by_tool(CAPTURE)` sur une revette → false.
  - `test_two_darts_then_net` : 2 × TORPOR puis CAPTURE → true, `captured` émis.
  - `test_ronce_never_captured` : ronce endormie (3 fléchettes), CAPTURE → false, `fell_asleep` émis.
  - `test_emerging_timidelle_capturable` : forcer l'état EMERGING, puis CAPTURE → true.
  - `test_burrowed_ignores_tools` : état BURROWED, puis TORPOR → `torpor.charges == 0`.
  - `test_non_panic_clamped` *(Review Focus 4)* : placer la plante à (19,9 ; 10) en FLEE, faire `_physics_process` × 30 avec une menace à (15,10) → toujours `contains` et état ≠ ESCAPED.
- [ ] **Step 3 :** lance les tests. Attendu : FAIL.
- [ ] **Step 4 :** implémente. `_physics_process` appelle la logique ; pour les tests, expose `step(delta: float) -> void`, que `_physics_process` appelle.
- [ ] **Step 5 :** lance les tests. Attendu : PASS.
- [ ] **Step 6 :** commit `Add plant actors with flee behaviours`.

### Task 9 : Héroïne, entrées et visée

**Files :**
- Create : `game/scripts/core/aim_assist.gd`
- Create : `game/scenes/heroine/heroine.tscn` + `heroine.gd`
- Create : `game/scenes/heroine/heroine_visual.tscn` (placeholder chibi §5.9)
- Modify : `game/project.godot` (section `[input]`)
- Test : `game/tests/unit/test_aim_assist.gd`

**Interfaces — Produces :**

`class_name AimAssist extends RefCounted` (statique)
```
enum Source { MOUSE, STICK, MOVE, AUTO }
const STRENGTH := { Source.MOUSE: 0.3, Source.STICK: 0.7, Source.MOVE: 0.7, Source.AUTO: 1.0 }
const CONE_HALF_ANGLE := 30.0
static func best_target(origin: Vector2, dir: Vector2, targets: PackedVector2Array, max_range: float) -> int  # -1 if none in cone; prefers smallest angle, then distance
static func assisted_direction(origin: Vector2, dir: Vector2, targets: PackedVector2Array, max_range: float, source: Source) -> Vector2  # dir slerped toward best target by STRENGTH[source]; dir unchanged if none
static func pick_source(current: Source, mouse_moved: bool, stick: Vector2, move: Vector2, pad_active: bool) -> Source
# stick.length() > 0.3 → STICK; elif mouse_moved → MOUSE; elif current == STICK and stick is idle and pad_active → MOVE; else current
```

`heroine.gd`, `class_name Heroine extends CharacterBody3D`, groupe `"heroine"`
```
const SPEED := 5.0
signal nightmare_hit
var aim_dir: Vector2          # unit XZ, always valid (defaults to facing)
var aim_source: AimAssist.Source
var lucidity: Lucidity        # injected by NightSession
func take_nightmare_hit() -> void   # if lucidity.take_hit(Time.get_ticks_msec() / 1000.0): emit nightmare_hit, play hurt blink
func facing() -> Vector2
```

Entrées (`[input]` dans `project.godot`) :
- `move_left/right/up/down` : ZQSD + WASD + flèches + stick gauche, zone morte 0,2.
- `aim_left/right/up/down` : stick droit.
- `use_tool` : clic gauche + gâchette droite (axe 5).
- `next_tool` : molette bas + RB. `prev_tool` : molette haut + LB.
- `tool_1/2/3` : touches 1, 2, 3.
- `pause` : Échap + Start.

Le mouvement est relatif à la caméra iso : la touche « haut » déplace vers le haut de l'écran, soit `(-1, -1).normalized()` en XZ pour un yaw de 45°. La visée souris projette le curseur sur le plan y = 0 (`Plane(Vector3.UP, 0).intersects_ray`).

- [ ] **Step 1 : tests.**
  - `test_best_target_in_cone` : origine (0,0), dir (1,0), cibles [(5,1), (5,−4), (−5,0)] → index 0.
  - `test_none_outside_cone` : cibles [(0,5)] → -1.
  - `test_assisted_strength` : en MOUSE, l'angle tourne de 30 % vers la cible ; en AUTO, la direction vise la cible.
  - `test_pick_source` *(Review Focus 5)* :
    - (MOUSE, stick (0,0,8)) → STICK ;
    - (STICK, mouse_moved) → MOUSE ;
    - (STICK, stick idle, pad_active, move non nul) → MOVE ;
    - (MOVE, stick idle, pad_active false, souris immobile) → MOVE : une manette débranchée garde la dernière direction, la visée n'est pas figée à zéro.
  - `test_heroine_default_aim` : `heroine.tscn` instancié → `aim_dir == Vector2(0, 1)` et jamais `Vector2.ZERO`.
- [ ] **Step 2 :** lance les tests. Attendu : FAIL.
- [ ] **Step 3 :** implémente `AimAssist`, l'InputMap, `Heroine` et le placeholder visuel : capsule-corps au haut rayé (4 anneaux de cylindres vert, rouge, orange et violet), tête sphère peau foncée, deux tresses (chaînes de sphères noires), lunettes (2 tores roses), collier doré (tore fin). Proportions chibi : tête ≈ 45 % de la hauteur, environ 1,1 m au total. Squash & stretch à la marche par tween d'échelle.
- [ ] **Step 4 :** lance les tests. Attendu : PASS.
- [ ] **Step 5 :** commit `Add heroine, input map and aim assist`.

### Task 10 : Outils (filet, tranquillisant, harpon) et ceinture d'outils

**Files :**
- Create : `game/scenes/tools/tool_belt.gd` (nœud enfant de Heroine)
- Create : `game/scenes/tools/projectile.tscn` + `projectile.gd`
- Create : `game/scenes/tools/net_swing.tscn` (visuel d'arc)
- Test : `game/tests/unit/test_tool_belt.gd`

**Interfaces — Produces :**

`class_name ToolBelt extends Node`
```
signal tool_changed(tool: ToolData)
signal tool_used(tool: ToolData)
signal plant_captured(plant: Plant)
var tools: Array[ToolData]   # set by NightSession from Herbarium.available_tools
var index: int
func set_tools(p_tools: Array[ToolData]) -> void
func current() -> ToolData
func select(i: int) -> void
func cycle(step: int) -> void
func try_use(origin: Vector3, aim_dir: Vector2) -> bool  # false while on cooldown
func tick(delta: float) -> void
```

- **Filet :** à l'usage, il appelle `hit_by_tool(CAPTURE)` sur chaque plante telle que `Steering.in_cone(origin, aim_dir, plant, 60, 2.0)`, et s'arrête à la première capture. En cas de raté sur une plante en FLEE, la plante prend un sprint ×1,5 pendant 0,8 s (exposé par `Plant.startle()`).
- **Tranquillisant et harpon :** ils lancent un `Projectile` (une `Area3D` en ligne droite à `projectile_speed`, détruite après `max_range`). Au contact d'une `Plant`, il appelle `hit_by_tool(effect)` puis se détruit.
- La direction de tir est `AimAssist.assisted_direction(...)` sur les positions des plantes non enterrées.

- [ ] **Step 1 : tests.**
  - `test_cycle_wraps` : 2 outils, `cycle(1)` × 2 → index 0.
  - `test_cooldown` : `try_use` → true, immédiatement → false, puis `tick(0.6)` → true (tranquillisant).
  - `test_harpoon_absent_by_default` : `set_tools` avec les outils du catalogue filtrés par un herbier neuf → 2 outils.
  - `test_net_captures_slowed_plant` : une plante à 1,5 m devant avec 2 charges → `try_use` du filet → `plant_captured` émis.
- [ ] **Step 2 :** lance les tests. Attendu : FAIL.
- [ ] **Step 3 :** implémente.
- [ ] **Step 4 :** lance les tests. Attendu : PASS.
- [ ] **Step 5 :** commit `Add net, tranquilizer and harpoon tools`.

### Task 11 : Caméra iso

**Files :** Create `game/scenes/camera/iso_camera.tscn` + `iso_camera.gd` · Test `game/tests/unit/test_iso_camera.gd`

**Interfaces — Produces :** `class_name IsoCamera extends Node3D`. Elle contient un `Camera3D` orthographique (`size = 22`, rotation pitch −35,264°, yaw 45°, distance 40 m).
```
@export var target_path: NodePath
@export var bounds: Rect2       # XZ rect the look-at point is clamped to
func snap_to_target() -> void
func focus_point() -> Vector3   # current clamped look-at point
```
Le suivi est lissé : `lerp` avec le facteur `1.0 - exp(-6.0 * delta)`.

- [ ] **Step 1 : test** `test_clamped_focus` : avec bounds (−10,−10,20,20) et une cible en (30,0,0), `snap_to_target()` donne `focus_point().x ≈ 10`. Vérifie aussi que le `Camera3D` est en projection `PROJECTION_ORTHOGONAL`.
- [ ] **Step 2 :** lance le test. Attendu : FAIL.
- [ ] **Step 3 :** implémente.
- [ ] **Step 4 :** lance le test. Attendu : PASS.
- [ ] **Step 5 :** commit `Add isometric follow camera`.

### Task 12 : GameState et NightSession (la nuit jouable)

**Files :**
- Create : `game/scripts/autoload/game_state.gd`. Modify `game/project.godot` : `[autoload] GameState="*res://scripts/autoload/game_state.gd"`.
- Create : `game/scenes/night/night.tscn` + `night_session.gd` (instancie Island, NightLighting, Heroine, IsoCamera, HUD placeholder, conteneur de plantes)
- Test : `game/tests/unit/test_game_state.gd`, `game/tests/unit/test_night_session.gd`

**Interfaces :**

`game_state.gd` (autoload `GameState`, `extends Node`)
```
signal herbarium_changed
var catalog: GameCatalog         # load("res://data/catalog.tres")
var herbarium: Herbarium
var save_path: String = SaveStore.DEFAULT_PATH
var last_night: Dictionary       # filled by finish_night, read by the wake screen
func load_save() -> void
func record(species: PlantSpecies) -> Dictionary   # herbarium.record + SaveStore.save immediately when new_species or new_detail (protects progress if the tab closes mid-night)
func finish_night(minutes: int, full: bool, captures: Array[StringName]) -> Dictionary
# returns and stores {"minutes", "full", "captures", "new_species": Array[StringName], "unlocked": Array[StringName], "dawn_memory": int, "best_minutes"}; applies register_night + apply_milestones, then saves
func start_night() -> void       # change_scene_to_file("res://scenes/night/night.tscn")
```

`night_session.gd`, `class_name NightSession extends Node3D`
```
signal night_ended(result: Dictionary)
var clock: NightClock
var lucidity: Lucidity
func spawn_tick() -> void    # keeps population at SpawnRules targets; spawns at island.random_point(rng, 2.0) at least 8 m from heroine
func end_night(full: bool) -> void
```

Branchements :
- **Capture** (`plant.captured`) : `clock.add_minutes(species.minutes_reward())`, `lucidity.register_capture()`, `GameState.record(species)`, ajout à `captures`, puis la plante est retirée.
- **Fuite :** `plant.escaped` → `lucidity.lose_petal()`.
- **Ronce endormie :** `plant.fell_asleep` sur une Ronce → `GameState.record(ronce)`.
- **Coup de cauchemar :** `heroine.nightmare_hit` ne fait que le retour visuel ; le pétale est déjà retiré par `Lucidity.take_hit`.
- **Lumière et vitesse :** `night_lighting.target_progress = clock.progress()` ; `NightLighting.glow_changed` → `set_glow` sur chaque plante. La vitesse des nouvelles plantes vient de `SpawnRules.speed_multiplier(clock.hour())`, et celle des plantes existantes est mise à jour à chaque capture.
- **Fins de nuit :** `clock.dawn_reached` → `end_night(true)` ; `lucidity.depleted` → `end_night(false)`. `end_night` fige le jeu, joue un fondu de 1 s (aube rose si full, flash blanc sinon), appelle `GameState.finish_night`, puis passe à `res://scenes/ui/wake.tscn`. La scène est créée en Tâche 13 ; jusque-là, un repli `print` suffit.
- **Outils :** ToolBelt reçoit les `ToolData` de `herbarium.available_tools(catalog)`.

- [ ] **Step 1 : tests.**
  - `test_game_state_record_saves_on_discovery` : `save_path = "user://test_gs.json"`, `record(revette)` → le fichier existe et le recharger donne revette découverte. Nettoie.
  - `test_finish_night_unlocks_harpoon` : herbier avec 3 capturables enregistrés, `finish_night(200, false, [])` → `unlocked == [&"harpoon"]`, `dawn_memory == -1`.
  - `test_finish_full_night_reveals_memory` : `finish_night(480, true, [])` → `dawn_memory == 0`.
  - `test_night_scene_loads` (smoke) : `night.tscn` s'instancie et entre dans l'arbre, sans erreur pendant 10 frames simulées (`await process_frame`, ou boucle de `step` manuelle). Ensuite `get_tree().get_nodes_in_group("plants").size() >= 6`.
  - `test_capture_advances_clock` : dans la session, émets `captured` d'une revette → `clock.minutes == 20` et `lucidity.streak == 1`.
  - `test_depleted_ends_night` : 5 × `lucidity.lose_petal()` → `night_ended` émis avec `full == false`.

  Pour les tests, `night_session` doit accepter `GameState.save_path` vers un fichier de test, et une option `@export var auto_change_scene := true` (mise à false par les tests).
- [ ] **Step 2 :** lance les tests. Attendu : FAIL.
- [ ] **Step 3 :** implémente. Mets temporairement `run/main_scene` sur `night.tscn` ; la Tâche 13 le remettra sur le titre.
- [ ] **Step 4 :** lance les tests. Attendu : PASS.
- [ ] **Step 5 :** lance le jeu (`godot --path game`) si un affichage est disponible. Sinon, garde la vérification pour la Tâche 15.
- [ ] **Step 6 :** commit `Wire the playable night session`.

### Task 13 : HUD et écrans (titre, réveil, herbier, pause)

**Files :**
- Create : `game/scenes/ui/theme.tres` (cartouches crème arrondies : `StyleBoxFlat` `#fdf6ea`, rayon 18, ombre douce, texte `#4a3f5c`)
- Create : `game/scenes/ui/hud.tscn` + `hud.gd`, `clock_flower.gd`
- Create : `game/scenes/ui/title.tscn`, `wake.tscn`, `herbarium.tscn`, `pause.tscn` (+ scripts)
- Modify : `game/scenes/main.tscn` → instancie `title.tscn` (ou remplace par le titre) ; `run/main_scene` reste `res://scenes/main.tscn`
- Test : `game/tests/unit/test_ui.gd`

**Interfaces — Produces :**
- `clock_flower.gd` (`class_name ClockFlower extends Control`) expose `func set_state(progress: float, petals: int, max_petals: int) -> void`. Son `_draw` trace :
  - un cadran crème ;
  - `max_petals` pétales en couronne, roses `#f3a6c0` et lavande `#c9b3f0` en alternance, les pétales perdus en contour gris ;
  - une aiguille-feuille verte `#7bbf6a` dont l'angle vaut `progress × TAU` (8 h = 1 tour, 0 h en haut) ;
  - le libellé « 3 h 20 » sous le cadran.
- `hud.gd` écoute les signaux de la session, sans aucun sondage dans `_process` : `clock.minutes_changed`, `lucidity.petal_lost/petal_regrown`, `tool_belt.tool_changed`, `plant captured`. Il affiche :
  - un toast de capture « +20 min · Rêvette », et « Nouvelle page ! » lors d'une découverte ;
  - la cartouche de l'outil actif.
- **Titre :** boutons « Commencer la nuit » (`GameState.start_night()`), « Herbier » et « Quitter » (masqué sur Web). Focus clavier ou manette sur le premier bouton.
- **Réveil :** lit `GameState.last_night` et affiche :
  - « Nuit complète — l'aube ! » ou « Réveil en sursaut à 3 h 20 » ;
  - les captures, les nouvelles pages, le déblocage (« Nouvel outil : Harpon ») et le souvenir d'aube révélé ;
  - le record ;
  - les boutons « Nuit suivante » et « Titre ».
- **Herbier :** une liste des 4 espèces. Les espèces inconnues apparaissent comme « ??? » en silhouette. Une page montre le nom, l'émotion, le nombre de captures, le fragment et les détails révélés. Une section « Souvenirs d'aube » montre ceux lus.
- **Pause :** `pause` met `get_tree().paused`, avec les boutons « Reprendre », « Herbier » et « Abandonner la nuit ». Abandonner = `end_night(false)` à l'heure actuelle.

- [ ] **Step 1 : tests.**
  - `test_clock_flower_state` : `set_state(0.5, 3, 5)` → les propriétés internes valent `needle_angle ≈ PI` et `lost == 2` (expose-les en lecture).
  - `test_wake_texts` : `GameState.last_night = {"minutes": 200, "full": false, ...}` puis instanciation de `wake.tscn` → le label titre contient « 3 h 20 ». Avec `full: true` → « l'aube ».
  - `test_herbarium_hides_unknown` : avec un herbier neuf, la page de timidelle affiche « ??? ».
  - `test_scenes_instantiate` : title, hud, herbarium et pause s'instancient sans erreur.
- [ ] **Step 2 :** lance les tests. Attendu : FAIL.
- [ ] **Step 3 :** implémente. Remets `run/main_scene` sur `res://scenes/main.tscn` (le titre).
- [ ] **Step 4 :** lance les tests. Attendu : PASS.
- [ ] **Step 5 :** commit `Add HUD clock flower and menus`.

### Task 14 : Presets d'export et build Web

**Files :** Modify `game/export_presets.cfg`

- [ ] **Step 1 :** ajoute les presets « Linux » (`Linux`, x86_64), « Windows Desktop » et « macOS » (universal, sans signature ni notarisation), avec les sorties `../build/<plateforme>/ChronoFlore.*`. Ne touche pas au preset « Web » existant.
- [ ] **Step 2 :** installe les templates Web 4.7.2 s'ils manquent : extrais seulement `templates/web_*` et `templates/version.txt` vers `~/.local/share/godot/export_templates/4.7.2.stable/`. Puis lance `mkdir -p build/web && godot --headless --path game --export-release "Web" ../build/web/index.html`. Attendu : code 0 et `build/web/index.html` + `.wasm` + `.pck` présents. `build/` est ignoré par git : ne commite rien dedans.
- [ ] **Step 3 :** lance la commande de test. Attendu : 0 failed.
- [ ] **Step 4 :** commit `Add desktop export presets`.

### Task 15 : Vérification manuelle et passe de réglage

**Files :** Create `docs/superpowers/plans/2026-10-29-tranche-verticale-playtest.md` (résultats)

- [ ] **Step 1 :** sers `build/web` en local (`python3 -m http.server -d build/web 8000`) et ouvre-le dans Chromium (Playwright). Prends des captures :
  - écran titre ;
  - début de nuit (pastel) ;
  - vers 4 h (indigo, plantes lumineuses) ;
  - écran de réveil.

  Joins-les au rapport.
- [ ] **Step 2 :** déroulé à vérifier et à noter :
  - une nuit complète jouée jusqu'à l'aube (pour accélérer, une option de debug `GameState.debug_minutes_multiplier`, uniquement en build debug) ;
  - un réveil en sursaut ;
  - le harpon débloqué après la Timidelle ;
  - l'herbier persistant après rechargement de l'onglet ;
  - le passage souris ↔ manette (si une manette est disponible ; sinon, « non vérifié »).
- [ ] **Step 3 :** relève les chiffres qui gênent : le rythme (une vingtaine de captures pour 8 h), la difficulté des Timidelles et la pression des Ronces. Ajuste-les dans les `.tres` ou les constantes, puis relance les tests.
- [ ] **Step 4 :** commit `Record vertical slice playtest notes`, puis pousse la branche.
