class_name NightSession
extends Node3D
## One playable night: wires the clock, lucidity, spawns, tools, lighting and camera together.
## The root keeps an identity transform; plants and projectiles live under it.

signal night_ended(result: Dictionary)
## A capture was counted in the herbarium; new_page is true on a first discovery.
signal capture_registered(species: PlantSpecies, new_page: bool)

const PLANT_SCENE := preload("res://scenes/plants/plant.tscn")
const WAKE_SCENE := "res://scenes/ui/wake.tscn"
const PAUSE_SCENE := preload("res://scenes/ui/pause.tscn")
const HEROINE_SCENE := preload("res://scenes/heroine/heroine.tscn")
const HEROINE_VISUAL := preload("res://scenes/heroine/heroine_visual.tscn")
const HERO_VISUAL := preload("res://scenes/heroine/hero2_visual.tscn")
## P2 starts this far from P1 (co-op): ~1.6 m to the screen right (see Heroine.SCREEN_RIGHT).
const P2_START_OFFSET := Vector2(1.1, -1.1)
## Seconds between population top-ups (progressive respawn).
const SPAWN_INTERVAL := 2.0
## Spawn points keep this distance to the island edge.
const SPAWN_MARGIN := 2.0
## Spawns keep this gap beyond the plants' alert radius from the heroine.
const SPAWN_ALERT_GAP := 3.0
const SPAWN_MIN_DISTANCE := Plant.ALERT_RADIUS + SPAWN_ALERT_GAP
## Random candidates tried before falling back to the farthest one.
const SPAWN_TRIES := 24
const TOOL_ORIGIN_HEIGHT := 0.5
const FADE_DURATION := 1.0
const DAWN_FADE_COLOR := Color(1.0, 0.82, 0.88)
const WAKE_FADE_COLOR := Color(1.0, 1.0, 1.0)
const HURT_FLASH_COLOR := Color(1.0, 0.55, 0.6, 0.35)
const HURT_FLASH_DURATION := 0.25

## Tests set this to false to stay on the night scene after it ends.
@export var auto_change_scene := true

var clock: NightClock
var lucidity: Lucidity
var captures: Array[StringName] = []
var ended: bool = false
## The open pause menu, or null.
var pause_menu: PauseMenu
## Playable characters: [the Heroine node] in solo, [P1, P2] in co-op. players[0] is `heroine`.
var players: Array[Heroine] = []
## Devices per player (DeviceAssignment), reapplied on every pad (un)plug.
var assignments: Array[Dictionary] = []

@onready var island: Island = $Island
@onready var heroine: Heroine = $Heroine
@onready var night_lighting: NightLighting = $NightLighting
@onready var camera: IsoCamera = $IsoCamera
@onready var plants_root: Node3D = $Plants
@onready var _belt: ToolBelt = $Heroine/ToolBelt
@onready var hud: Hud = $HUD/Hud
@onready var _hud_layer: CanvasLayer = $HUD
@onready var _fade: ColorRect = $Fade/ColorRect

var _rng := RandomNumberGenerator.new()
var _spawn_timer: float = 0.0
var _plant_glow: float = 0.0
var _flash_tween: Tween
var _last_xz: PackedVector2Array = PackedVector2Array() ## players' XZ at the last leash check

func _ready() -> void:
	_rng.randomize()
	GameState.begin_night()
	clock = NightClock.new()
	lucidity = Lucidity.new()
	clock.minutes_changed.connect(_on_minutes_changed)
	clock.dawn_reached.connect(end_night.bind(true))
	lucidity.depleted.connect(end_night.bind(false))

	setup_players(GameState.mode)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	hud.bind(self, _belt)

	night_lighting.target_progress = 0.0
	night_lighting.set_display_progress(0.0)
	_plant_glow = float(NightPalette.sample(0.0)["plant_glow"])
	night_lighting.glow_changed.connect(_on_glow_changed)

	camera.bounds = _outline_rect(island.shape)
	camera.snap_to_target()

	_fade.color = Color(WAKE_FADE_COLOR, 0.0)
	spawn_tick()

func _physics_process(delta: float) -> void:
	if ended:
		return
	for player in players:
		var p := Vector2(player.global_position.x, player.global_position.z)
		var clamped := island.shape.clamp_inside(p, Heroine.EDGE_MARGIN)
		if clamped != p:
			player.global_position = Vector3(clamped.x, player.global_position.y, clamped.y)
	apply_leash()
	feed_threats()
	for player in players:
		var belt := _belt_of(player)
		belt.tick(delta)
		if Input.is_action_pressed(player.action(&"use_tool")):
			belt.try_use(player.global_position + Vector3.UP * TOOL_ORIGIN_HEIGHT, player.aim_dir)
	_spawn_timer += delta
	if _spawn_timer >= SPAWN_INTERVAL:
		_spawn_timer = 0.0
		spawn_tick()

func _unhandled_input(event: InputEvent) -> void:
	if ended:
		return
	if event.is_action_pressed("pause"):
		open_pause()
		get_viewport().set_input_as_handled()
		return
	for player in players:
		var belt := _belt_of(player)
		if event.is_action_pressed(player.action(&"next_tool")):
			belt.cycle(1)
		elif event.is_action_pressed(player.action(&"prev_tool")):
			belt.cycle(-1)
		else:
			for i in 3:
				if event.is_action_pressed(player.action(StringName("tool_%d" % (i + 1)))):
					belt.select(i)

## Builds the players for a mode: the scene's Heroine node is always P1 (heroine visual, or the
## hero's in SOLO_HERO); co-op adds P2 (the hero). Safe to call again: extra players are removed.
func setup_players(p_mode: GameState.Mode) -> void:
	for i in range(players.size() - 1, 0, -1):
		var extra := players[i]
		players.remove_at(i)
		extra.remove_from_group("heroine")
		extra.queue_free()
	players.clear()
	heroine.player_index = 0
	heroine.visual_scene = HERO_VISUAL if p_mode == GameState.Mode.SOLO_HERO else HEROINE_VISUAL
	_add_player(heroine)
	if p_mode == GameState.Mode.COOP:
		var p2 := HEROINE_SCENE.instantiate() as Heroine
		p2.name = "Hero"
		p2.player_index = 1
		p2.visual_scene = HERO_VISUAL
		add_child(p2)
		move_child(p2, heroine.get_index() + 1)
		_add_player(p2)
	var start := island.shape.centroid()
	for i in players.size():
		var at := start + P2_START_OFFSET * i
		players[i].global_position = Vector3(at.x, island.ground_height(), at.y)
	_last_xz = player_points()
	assignments.clear()
	apply_devices(Input.get_connected_joypads())
	var targets: Array[Node3D] = []
	for player in players:
		targets.append(player)
	camera.set_targets(targets)

func is_coop() -> bool:
	return players.size() > 1

## Players' XZ positions, in player order.
func player_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for player in players:
		out.append(Vector2(player.global_position.x, player.global_position.z))
	return out

## Every plant reacts to its nearest player: position, aim, and who its contact hits.
func feed_threats() -> void:
	var points := player_points()
	for plant in live_plants():
		var i := CoopRules.nearest(plant.xz(), points)
		if i >= 0:
			plant.set_threat(points[i], players[i].aim_dir, players[i])

## Co-op leash: beyond LEASH_DISTANCE the players are pulled back together, each by the share
## of the gap they walked away since the last check (whoever wanders off is the one held).
func apply_leash() -> void:
	var points := player_points()
	if points.size() == 2 and _last_xz.size() == 2:
		var a := points[0]
		var b := points[1]
		if a.distance_to(b) > CoopRules.LEASH_DISTANCE:
			var sep := (b - a).normalized()
			var out_a := maxf((a - _last_xz[0]).dot(-sep), 0.0)
			var out_b := maxf((b - _last_xz[1]).dot(sep), 0.0)
			if out_a <= 1e-6 and out_b > 1e-6:
				b = CoopRules.leash(b, a)
			elif out_b <= 1e-6 and out_a > 1e-6:
				a = CoopRules.leash(a, b)
			else:
				var share_b := 0.5 if out_a + out_b <= 1e-6 else out_b / (out_a + out_b)
				var excess := a.distance_to(b) - CoopRules.LEASH_DISTANCE
				b -= sep * excess * share_b
				a += sep * excess * (1.0 - share_b)
			_place_player(players[0], a)
			_place_player(players[1], b)
			points = player_points()
	_last_xz = points

func _place_player(player: Heroine, p: Vector2) -> void:
	player.global_position = Vector3(p.x, player.global_position.y, p.y)

## Reassigns devices for the connected pads (DeviceAssignment rules) and rebuilds the bindings;
## keyboard halves aim AUTO, only the keyboard-mouse player reads the mouse.
func apply_devices(pad_ids: Array[int]) -> void:
	assignments = DeviceAssignment.reassign(assignments, pad_ids, is_coop())
	DeviceAssignment.apply(assignments)
	for i in players.size():
		var player := players[i]
		var kind := DeviceAssignment.Kind.KEYBOARD_MOUSE
		var device := DeviceAssignment.ALL_PADS
		if i < assignments.size():
			kind = int(assignments[i]["kind"]) as DeviceAssignment.Kind
			device = int(assignments[i]["device"])
		player.auto_aim = DeviceAssignment.auto_aim(kind)
		player.uses_mouse = DeviceAssignment.uses_mouse(kind)
		player.pad_device = device
		if not player.auto_aim and player.aim_source == AimAssist.Source.AUTO:
			player.aim_source = AimAssist.Source.MOVE
		if not player.uses_mouse and player.aim_source == AimAssist.Source.MOUSE:
			player.aim_source = AimAssist.Source.MOVE

func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	apply_devices(Input.get_connected_joypads())

func _add_player(player: Heroine) -> void:
	players.append(player)
	player.lucidity = lucidity
	player.island = island.shape
	if not player.nightmare_hit.is_connected(_on_nightmare_hit):
		player.nightmare_hit.connect(_on_nightmare_hit)
	_belt_of(player).set_tools(_available_tools())

func _belt_of(player: Heroine) -> ToolBelt:
	return player.get_node("ToolBelt") as ToolBelt

## Plants still in play (not captured, escaping or being freed).
func live_plants() -> Array[Plant]:
	var result: Array[Plant] = []
	for child in plants_root.get_children():
		var plant := child as Plant
		if plant != null and not plant.is_queued_for_deletion() \
				and plant.state != Plant.State.CAPTURED and plant.state != Plant.State.ESCAPED:
			result.append(plant)
	return result

## Tops up gentle plants and nightmares (hostiles, counted separately) to the SpawnRules targets.
func spawn_tick() -> void:
	if ended:
		return
	var hour := clock.hour()
	var gentle := 0
	var nightmares := 0
	for plant in live_plants():
		if plant.species.hostile:
			nightmares += 1
		else:
			gentle += 1
	var eligible := SpawnRules.eligible_capturables(GameState.catalog, hour)
	for i in range(gentle, CoopRules.population(SpawnRules.target_population(hour), is_coop())):
		var species := SpawnRules.pick(eligible, _rng)
		if species == null:
			break
		add_plant(species, spawn_point())
	var nightmare_species := SpawnRules.eligible_hostiles(GameState.catalog, hour)
	if nightmare_species.is_empty():
		return
	for i in range(nightmares, CoopRules.nightmares(SpawnRules.nightmare_count(hour), is_coop())):
		add_plant(nightmare_species[_rng.randi_range(0, nightmare_species.size() - 1)], spawn_point())

## Random island point at least SPAWN_MIN_DISTANCE from every player, else the farthest tried
## (from its nearest player).
func spawn_point() -> Vector2:
	var points := player_points()
	var best := Vector2.ZERO
	var best_d := -1.0
	for i in SPAWN_TRIES:
		var p := island.shape.random_point(_rng, SPAWN_MARGIN)
		var d := INF
		for h in points:
			d = minf(d, p.distance_to(h))
		if d >= SPAWN_MIN_DISTANCE:
			return p
		if d > best_d:
			best_d = d
			best = p
	return best

func add_plant(species: PlantSpecies, at: Vector2) -> Plant:
	var plant := PLANT_SCENE.instantiate() as Plant
	plants_root.add_child(plant)
	plant.setup(species, island.shape, SpawnRules.speed_multiplier(clock.hour()))
	plant.global_position = Vector3(at.x, island.ground_height(), at.y)
	plant.set_glow(_plant_glow)
	plant.captured.connect(_on_plant_captured)
	plant.escaped.connect(_on_plant_escaped)
	return plant

## Freezes the night, saves the result, then fades (dawn pink or wake-up white) to the wake screen.
func end_night(full: bool) -> void:
	if ended:
		return
	ended = true
	_freeze()
	# Saved before the fade so the night is never lost if the tab closes during it.
	var result := GameState.finish_night(clock.minutes, full, captures)
	night_ended.emit(result)
	if _flash_tween != null:
		_flash_tween.kill()
	_fade.color = Color(DAWN_FADE_COLOR if full else WAKE_FADE_COLOR, 0.0)
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_DURATION)
	tween.tween_callback(_go_to_wake)

func _on_plant_captured(plant: Plant) -> void:
	if ended:
		return
	var species := plant.species
	# Herbarium first: the minutes below may reach dawn and end the night.
	lucidity.register_capture()
	var record := GameState.record(species)
	capture_registered.emit(species, bool(record["new_species"]))
	captures.append(species.id)
	if plant.state != Plant.State.CAPTURED and not plant.is_queued_for_deletion():
		plant.queue_free() # a real capture frees itself after its shrink tween
	clock.add_minutes(species.minutes_reward())
	var speed := SpawnRules.speed_multiplier(clock.hour())
	for p in live_plants():
		p.speed_multiplier = speed

func _on_plant_escaped(_plant: Plant) -> void:
	if not ended:
		lucidity.lose_petal()

## Visual feedback only: Lucidity.take_hit already removed the petal.
func _on_nightmare_hit() -> void:
	if ended:
		return
	if _flash_tween != null:
		_flash_tween.kill()
	_fade.color = HURT_FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(_fade, "color:a", 0.0, HURT_FLASH_DURATION)

func _on_minutes_changed(_minutes: int) -> void:
	night_lighting.target_progress = clock.progress()

func _on_glow_changed(value: float) -> void:
	_plant_glow = value
	for plant in live_plants():
		plant.set_glow(value)

## Deferred: the night can end mid-physics (a Ronce hit), and disabling a body there removes it
## from the physics space while it is still moving this frame.
func _freeze() -> void:
	for child in get_children():
		if child != _fade.get_parent():
			child.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)

func _go_to_wake() -> void:
	if not auto_change_scene:
		return
	if ResourceLoader.exists(WAKE_SCENE):
		get_tree().change_scene_to_file(WAKE_SCENE)

func _available_tools() -> Array[ToolData]:
	var result: Array[ToolData] = []
	for id in GameState.herbarium.available_tools(GameState.catalog):
		var tool := GameState.catalog.tool_by_id(id)
		if tool != null:
			result.append(tool)
	return result

static func _outline_rect(shape: IslandShape) -> Rect2:
	if shape.outline.is_empty():
		return Rect2()
	var rect := Rect2(shape.outline[0], Vector2.ZERO)
	for v in shape.outline:
		rect = rect.expand(v)
	return rect

## Pauses the tree and shows the pause menu (which keeps running while paused).
func open_pause() -> void:
	if ended or pause_menu != null:
		return
	get_tree().paused = true
	pause_menu = PAUSE_SCENE.instantiate() as PauseMenu
	pause_menu.resumed.connect(func() -> void: pause_menu = null)
	pause_menu.abandoned.connect(func() -> void:
		pause_menu = null
		end_night(false))
	_hud_layer.add_child(pause_menu)

func _exit_tree() -> void:
	DeviceAssignment.restore() # the project's (solo) bindings back for menus and the next night
	if pause_menu != null and is_inside_tree():
		get_tree().paused = false
