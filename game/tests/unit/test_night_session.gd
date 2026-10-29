extends "res://tests/test_case.gd"

const NIGHT_SCENE := "res://scenes/night/night.tscn"
const PATH := "user://test_night.json"

var _saved_path: String
var _saved_herbarium: Herbarium

func _session() -> NightSession:
	_saved_path = GameState.save_path
	_saved_herbarium = GameState.herbarium
	GameState.save_path = PATH
	GameState.herbarium = Herbarium.new()
	_remove_file()
	var s := (load(NIGHT_SCENE) as PackedScene).instantiate() as NightSession
	s.auto_change_scene = false
	tree.root.add_child(s)
	await tree.process_frame
	return s

func _end(s: NightSession) -> void:
	s.free()
	_remove_file()
	GameState.save_path = _saved_path
	GameState.herbarium = _saved_herbarium

func _remove_file() -> void:
	for p in [PATH, PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func _count(s: NightSession, gentle: bool) -> int:
	var n := 0
	for p in s.live_plants():
		if p.species.hostile != gentle:
			n += 1
	return n

func test_night_scene_loads() -> void:
	var s: NightSession = await _session()
	for i in 10:
		await tree.process_frame
	assert_true(tree.get_nodes_in_group("plants").size() >= 6, "at least 6 plants in play")
	assert_true(s.clock != null and s.lucidity != null, "clock and lucidity exist")
	var heroine := s.get_node("Heroine") as Heroine
	assert_true(heroine.lucidity == s.lucidity, "heroine shares the session lucidity")
	var belt := heroine.get_node("ToolBelt") as ToolBelt
	assert_eq(belt.tools.size(), 2, "fresh herbarium: net + tranquilizer")
	_end(s)

func test_spawn_keeps_targets_and_distance() -> void:
	var s: NightSession = await _session()
	assert_eq(_count(s, true), SpawnRules.target_population(0.0), "capturable population at target")
	assert_eq(_count(s, false), SpawnRules.nightmare_count(0.0), "nightmares counted separately")
	var plants := s.live_plants()
	plants[0].queue_free()
	await tree.process_frame
	s.spawn_tick()
	assert_eq(_count(s, true) + _count(s, false), plants.size(), "spawn_tick refills the population")
	_end(s)

## Spawns must stay within the visible ground so a new plant can be seen (16:9 viewport).
func test_spawn_distance_fits_the_camera_view() -> void:
	var half_height_ground := IsoCamera.ORTHO_SIZE * 0.5 / sin(deg_to_rad(-IsoCamera.PITCH_DEG))
	var half_width_ground := IsoCamera.ORTHO_SIZE * 0.5 * 16.0 / 9.0
	var visible := minf(half_height_ground, half_width_ground)
	assert_true(NightSession.SPAWN_MIN_DISTANCE <= visible - 1.0,
			"spawn min distance %.2f <= visible half-extent %.2f - 1 m" % [NightSession.SPAWN_MIN_DISTANCE, visible])

func test_spawn_point_far_from_heroine() -> void:
	var s: NightSession = await _session()
	var shape: IslandShape = s.island.shape
	assert_true(NightSession.SPAWN_MIN_DISTANCE >= Plant.ALERT_RADIUS + 2.0, "spawns outside the alert radius + 2 m")
	assert_true(Plant.CALM_DISTANCE > Plant.ALERT_RADIUS, "calm distance beyond the alert radius")
	s.heroine.global_position = Vector3(-8.0, 0.0, 4.0)
	for i in 20:
		var p := s.spawn_point()
		assert_true(shape.contains(p), "spawn point on the island")
		assert_true(shape.is_clear(p, NightSession.SPAWN_MARGIN), "spawn point not in the pond")
		assert_true(p.distance_to(Vector2(-8.0, 4.0)) >= NightSession.SPAWN_MIN_DISTANCE, "spawn point far enough")
	# From the centre of the meadow the minimum distance is always achievable.
	var c := shape.centroid()
	s.heroine.global_position = Vector3(c.x, 0.0, c.y)
	for i in 50:
		var p := s.spawn_point()
		assert_true(p.distance_to(c) >= NightSession.SPAWN_MIN_DISTANCE, "min distance achieved from the centre")
		assert_true(shape.is_clear(p, NightSession.SPAWN_MARGIN), "centre spawn not in the pond")
	_end(s)

func test_capture_advances_clock() -> void:
	var s: NightSession = await _session()
	var revette := GameState.catalog.species_by_id(&"revette")
	var plant := s.add_plant(revette, s.island.shape.centroid())
	plant.captured.emit(plant)
	assert_eq(s.clock.minutes, 20, "common capture adds 20 min")
	assert_eq(s.lucidity.streak, 1, "streak counted")
	assert_true(GameState.herbarium.is_discovered(&"revette"), "recorded in the herbarium")
	assert_false(s.live_plants().has(plant), "captured plant removed from play")
	_end(s)

func test_sleeping_hostile_is_recorded_only_when_captured() -> void:
	var s: NightSession = await _session()
	var ronce := GameState.catalog.species_by_id(&"ronce_angoisse")
	var plant := s.add_plant(ronce, s.island.shape.centroid())
	for i in Torpor.SLEEP_CHARGES:
		plant.hit_by_tool(ToolData.Effect.TORPOR)
	assert_true(plant.torpor.is_asleep(), "ronce asleep")
	assert_false(GameState.herbarium.is_discovered(&"ronce_angoisse"), "no page from a mere sleep")
	assert_eq(s.clock.minutes, 0, "sleep gives no minutes")
	assert_true(plant.hit_by_tool(ToolData.Effect.CAPTURE), "netted while asleep")
	assert_true(GameState.herbarium.is_discovered(&"ronce_angoisse"), "ronce page from the capture")
	assert_eq(s.clock.minutes, 40, "a captured hostile adds 40 min")
	_end(s)

func test_escape_loses_petal() -> void:
	var s: NightSession = await _session()
	var plant := s.live_plants()[0]
	plant.escaped.emit(plant)
	assert_eq(s.lucidity.petals, 4, "escape costs a petal")
	_end(s)

func test_depleted_ends_night() -> void:
	var s: NightSession = await _session()
	var got: Array[Dictionary] = []
	s.night_ended.connect(func(r: Dictionary) -> void: got.append(r))
	for i in 5:
		s.lucidity.lose_petal()
	assert_eq(got.size(), 1, "night_ended emitted once")
	if got.size() == 1:
		assert_false(bool(got[0]["full"]), "not a full night")
	_end(s)

func test_dawn_ends_full_night() -> void:
	var s: NightSession = await _session()
	var got: Array[Dictionary] = []
	s.night_ended.connect(func(r: Dictionary) -> void: got.append(r))
	s.clock.add_minutes(480)
	s.lucidity.lose_petal() # after the end: ignored
	assert_eq(got.size(), 1, "night_ended emitted once")
	if got.size() == 1:
		assert_true(bool(got[0]["full"]), "full night")
		assert_eq(int(got[0]["dawn_memory"]), 0, "first dawn memory revealed")
	_end(s)

func test_end_night_freezes_after_the_frame() -> void:
	var s: NightSession = await _session()
	s.end_night(false)
	# Deferred: a Ronce hit can end the night mid-physics while that plant is still moving.
	assert_eq(s.plants_root.process_mode, Node.PROCESS_MODE_INHERIT, "not frozen mid-frame")
	await tree.process_frame
	assert_eq(s.plants_root.process_mode, Node.PROCESS_MODE_DISABLED, "plants frozen")
	assert_eq(s.heroine.process_mode, Node.PROCESS_MODE_DISABLED, "heroine frozen")
	assert_eq(s.get_node("Fade").process_mode, Node.PROCESS_MODE_INHERIT, "fade keeps running")
	assert_true(s.ended, "ended")
	_end(s)

## I4: the Web build has no shader cache; the ground-sign shader and the omni light pass are
## drawn invisibly at night start, then freed.
func test_night_start_prewarms_shaders() -> void:
	var s: NightSession = await _session()
	var nodes := s.prewarm_nodes()
	assert_eq(nodes.size(), 3, "a disc, a lane and a light")
	var marks := 0
	for node in nodes:
		if node is GroundMark:
			marks += 1
			assert_near(float((node as GroundMark).material().get_shader_parameter("opacity")), 0.0, 1e-6, "invisible sign")
			assert_true(node.visible, "drawn (a hidden node compiles nothing)")
		elif node is OmniLight3D:
			assert_eq((node as OmniLight3D).light_color, Color.BLACK, "black light: adds nothing")
			assert_true(node.visible, "light on")
	assert_eq(marks, 2, "disc and lane")
	for i in NightSession.PREWARM_FRAMES + 1:
		await tree.process_frame
	assert_eq(s.prewarm_nodes().size(), 0, "freed after a few frames")
	assert_true(s.get_node_or_null("PrewarmLight") == null or s.get_node("PrewarmLight").is_queued_for_deletion(), "light gone")
	_end(s)

func test_plant_rim_variant_on_from_the_start() -> void:
	var s: NightSession = await _session()
	var plant := s.live_plants()[0]
	var model := plant.get_node("Visual").get_child(0) as PlantModelVisual
	for mat in model.materials():
		assert_true(mat.rim_enabled, "rim on at 0 h (no recompile at 2 h)")
		assert_near(mat.rim, 0.0, 1e-6, "but no rim by day")
	_end(s)
