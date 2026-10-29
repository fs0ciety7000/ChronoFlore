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

func _ready() -> void:
	_rng.randomize()
	GameState.begin_night()
	clock = NightClock.new()
	lucidity = Lucidity.new()
	clock.minutes_changed.connect(_on_minutes_changed)
	clock.dawn_reached.connect(end_night.bind(true))
	lucidity.depleted.connect(end_night.bind(false))

	var start := island.shape.centroid()
	heroine.global_position = Vector3(start.x, island.ground_height(), start.y)
	heroine.lucidity = lucidity
	heroine.island = island.shape
	heroine.nightmare_hit.connect(_on_nightmare_hit)
	_belt.set_tools(_available_tools())
	hud.bind(self, _belt)

	night_lighting.target_progress = 0.0
	night_lighting.set_display_progress(0.0)
	_plant_glow = float(NightPalette.sample(0.0)["plant_glow"])
	night_lighting.glow_changed.connect(_on_glow_changed)

	camera.set_target(heroine)
	camera.bounds = _outline_rect(island.shape)
	camera.snap_to_target()

	_fade.color = Color(WAKE_FADE_COLOR, 0.0)
	spawn_tick()

func _physics_process(delta: float) -> void:
	if ended:
		return
	var h := _heroine_xz()
	var clamped := island.shape.clamp_inside(h, Heroine.EDGE_MARGIN)
	if clamped != h:
		heroine.global_position = Vector3(clamped.x, heroine.global_position.y, clamped.y)
		h = clamped
	for plant in live_plants():
		plant.set_threat(h, heroine.aim_dir)
	_belt.tick(delta)
	if Input.is_action_pressed("use_tool"):
		_belt.try_use(heroine.global_position + Vector3.UP * TOOL_ORIGIN_HEIGHT, heroine.aim_dir)
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
	elif event.is_action_pressed("next_tool"):
		_belt.cycle(1)
	elif event.is_action_pressed("prev_tool"):
		_belt.cycle(-1)
	else:
		for i in 3:
			if event.is_action_pressed("tool_%d" % (i + 1)):
				_belt.select(i)

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
	for i in range(gentle, SpawnRules.target_population(hour)):
		var species := SpawnRules.pick(eligible, _rng)
		if species == null:
			break
		add_plant(species, spawn_point())
	var nightmare_species := SpawnRules.eligible_hostiles(GameState.catalog, hour)
	if nightmare_species.is_empty():
		return
	for i in range(nightmares, SpawnRules.nightmare_count(hour)):
		add_plant(nightmare_species[_rng.randi_range(0, nightmare_species.size() - 1)], spawn_point())

## Random island point at least SPAWN_MIN_DISTANCE from the heroine, else the farthest tried.
func spawn_point() -> Vector2:
	var h := _heroine_xz()
	var best := Vector2.ZERO
	var best_d := -1.0
	for i in SPAWN_TRIES:
		var p := island.shape.random_point(_rng, SPAWN_MARGIN)
		var d := p.distance_to(h)
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

func _heroine_xz() -> Vector2:
	return Vector2(heroine.global_position.x, heroine.global_position.z)

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
	if pause_menu != null and is_inside_tree():
		get_tree().paused = false
