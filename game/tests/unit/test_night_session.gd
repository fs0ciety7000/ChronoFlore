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

func _count(s: NightSession, capturable: bool) -> int:
	var n := 0
	for p in s.live_plants():
		if p.species.capturable == capturable:
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

func test_spawn_point_far_from_heroine() -> void:
	var s: NightSession = await _session()
	var shape: IslandShape = s.island.shape
	s.heroine.global_position = Vector3(-5.0, 0.0, 0.0) # west side: plenty of room >= 8 m east
	for i in 20:
		var p := s.spawn_point()
		assert_true(shape.contains(p), "spawn point on the island")
		assert_true(p.distance_to(Vector2(-5.0, 0.0)) >= NightSession.SPAWN_MIN_DISTANCE, "spawn point at least 8 m away")
	# From the centre, 8 m is rarely reachable on the small plateau: fall back to a far point.
	var c := shape.centroid()
	s.heroine.global_position = Vector3(c.x, 0.0, c.y)
	for i in 20:
		assert_true(s.spawn_point().distance_to(c) >= 5.0, "fallback keeps spawns away from the heroine")
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

func test_sleeping_ronce_is_recorded() -> void:
	var s: NightSession = await _session()
	var ronce := GameState.catalog.species_by_id(&"ronce_angoisse")
	var plant := s.add_plant(ronce, s.island.shape.centroid())
	plant.fell_asleep.emit(plant)
	assert_true(GameState.herbarium.is_discovered(&"ronce_angoisse"), "ronce page from sleep")
	assert_eq(s.clock.minutes, 0, "sleep gives no minutes")
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
