extends "res://tests/test_case.gd"

const PLANT_SCENE := "res://scenes/plants/plant.tscn"
const DT := 1.0 / 60.0

var _root: Node3D

func _square() -> IslandShape:
	var s := IslandShape.new()
	s.outline = PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(20, 20), Vector2(0, 20)])
	return s

func _spawn(species_id: String, at: Vector2 = Vector2(10, 10)) -> Plant:
	if _root == null:
		_root = Node3D.new()
		tree.root.add_child(_root)
	var plant := (load(PLANT_SCENE) as PackedScene).instantiate() as Plant
	_root.add_child(plant)
	var species := load("res://data/species/%s.tres" % species_id) as PlantSpecies
	plant.setup(species, _square(), 1.0)
	plant.position = Vector3(at.x, 0.0, at.y)
	return plant

func _xz(plant: Plant) -> Vector2:
	return Vector2(plant.position.x, plant.position.z)

func _cleanup() -> void:
	if _root != null:
		_root.free()
		_root = null

func _steps(plant: Plant, n: int, dt: float = DT) -> void:
	for i in n:
		plant.step(dt)

# Keeps the heroine 2 m from the plant, on the island side, every frame.
func _chase(plant: Plant, n: int) -> void:
	for i in n:
		if plant.state == Plant.State.ESCAPED:
			return
		plant.set_threat(_xz(plant) + (Vector2(10, 10) - _xz(plant)).limit_length(2.0), Vector2(-1, 0))
		plant.step(DT)

func test_plant_scene_basics() -> void:
	var plant := _spawn("revette")
	assert_true(plant.is_in_group("plants"), "in group plants")
	assert_eq(plant.state, Plant.State.WANDER, "starts wandering")
	assert_true(plant.torpor != null, "has torpor")
	assert_true(plant.get_node("Visual").get_child_count() > 0, "species visual instantiated")
	_cleanup()

func test_species_have_visuals() -> void:
	for id in ["revette", "nostalgerbe", "timidelle", "ronce_angoisse"]:
		var species := load("res://data/species/%s.tres" % id) as PlantSpecies
		assert_true(species.visual_scene != null, "%s has a visual scene" % id)

func test_net_fails_on_fresh_plant() -> void:
	var plant := _spawn("revette")
	var got: Array[int] = [0]
	plant.captured.connect(func(_p: Plant) -> void: got[0] += 1)
	assert_false(plant.hit_by_tool(ToolData.Effect.CAPTURE), "net fails without torpor")
	assert_eq(got[0], 0, "no captured signal")
	assert_true(plant.state != Plant.State.CAPTURED, "not captured")
	_cleanup()

func test_two_darts_then_net() -> void:
	var plant := _spawn("revette")
	var got: Array[Plant] = []
	plant.captured.connect(func(p: Plant) -> void: got.append(p))
	plant.hit_by_tool(ToolData.Effect.TORPOR)
	plant.hit_by_tool(ToolData.Effect.TORPOR)
	assert_true(plant.hit_by_tool(ToolData.Effect.CAPTURE), "net captures after 2 darts")
	assert_eq(got.size(), 1, "captured emitted once")
	if got.size() == 1:
		assert_true(got[0] == plant, "captured carries the plant")
	assert_eq(plant.state, Plant.State.CAPTURED, "state CAPTURED")
	assert_false(plant.hit_by_tool(ToolData.Effect.CAPTURE), "cannot be captured twice")
	assert_eq(got.size(), 1, "still one captured signal")
	_cleanup()

func test_pin_then_net() -> void:
	var plant := _spawn("nostalgerbe")
	plant.hit_by_tool(ToolData.Effect.PIN)
	assert_true(plant.torpor.is_pinned(), "pinned")
	assert_true(plant.hit_by_tool(ToolData.Effect.CAPTURE), "net captures a pinned plant")
	_cleanup()

func test_emerging_timidelle_capturable() -> void:
	var plant := _spawn("timidelle")
	plant.state = Plant.State.EMERGING
	assert_true(plant.is_emerging(), "is_emerging")
	assert_true(plant.hit_by_tool(ToolData.Effect.CAPTURE), "emerging timidelle netted without torpor")
	_cleanup()

func test_burrowed_ignores_tools() -> void:
	var plant := _spawn("timidelle")
	plant.state = Plant.State.BURROWED
	assert_false(plant.hit_by_tool(ToolData.Effect.TORPOR), "dart returns false")
	assert_eq(plant.torpor.charges, 0, "no charge while burrowed")
	plant.hit_by_tool(ToolData.Effect.PIN)
	assert_false(plant.torpor.is_pinned(), "no pin while burrowed")
	assert_false(plant.hit_by_tool(ToolData.Effect.CAPTURE), "no capture while burrowed")
	_cleanup()

func test_non_panic_clamped() -> void:
	var plant := _spawn("revette", Vector2(19.9, 10))
	var island := _square()
	plant.state = Plant.State.FLEE
	plant.set_threat(Vector2(15, 10), Vector2(1, 0))
	var always_in := true
	for i in 30:
		plant.step(DT)
		if not island.contains(_xz(plant)):
			always_in = false
	assert_true(always_in, "always inside the island")
	assert_true(plant.state != Plant.State.ESCAPED, "did not escape")
	assert_true(island.distance_to_edge(_xz(plant)) >= 0.29, "kept the 0.3 m margin")
	_cleanup()

func test_slowed_plant_never_falls() -> void:
	# Review Focus 4: a slowed plant chased against the edge never leaves the island.
	var plant := _spawn("revette", Vector2(0.4, 10))
	var island := _square()
	var always_in := true
	for i in 300:
		if i % 120 == 0:
			plant.hit_by_tool(ToolData.Effect.TORPOR)
		plant.set_threat(_xz(plant) + Vector2(1.5, 0), Vector2(-1, 0))
		plant.step(DT)
		if not island.contains(_xz(plant)):
			always_in = false
	assert_true(always_in, "slowed plant always on the island")
	assert_true(plant.state != Plant.State.ESCAPED and plant.state != Plant.State.PANIC, "slowed plant not escaped")
	_cleanup()

func test_alert_starts_flight() -> void:
	var plant := _spawn("revette")
	plant.set_threat(Vector2(10 + Plant.ALERT_RADIUS + 2.0, 10), Vector2(-1, 0))
	_steps(plant, 30)
	assert_eq(plant.state, Plant.State.WANDER, "ignores a far heroine")
	plant.set_threat(Vector2(13, 10), Vector2(-1, 0))
	_steps(plant, 60)
	assert_eq(plant.state, Plant.State.FLEE, "flees a near heroine")
	_cleanup()

func test_panic_then_escape() -> void:
	var plant := _spawn("revette", Vector2(10, 10))
	var gone: Array[int] = [0]
	plant.escaped.connect(func(_p: Plant) -> void: gone[0] += 1)
	plant.state = Plant.State.FLEE
	_chase(plant, int(plant.species.panic_after / DT) + 2)
	assert_eq(plant.state, Plant.State.PANIC, "panics after panic_after seconds")
	_chase(plant, 600)
	assert_eq(plant.state, Plant.State.ESCAPED, "panicked plant escapes")
	assert_eq(gone[0], 1, "escaped emitted once")
	var y_before := plant.position.y
	plant.step(0.5)
	assert_true(plant.position.y < y_before, "falls after escaping")
	plant.step(0.6)
	assert_true(plant.is_queued_for_deletion(), "freed after 1 s")
	_cleanup()

func test_escape_runs_to_visible_edge_before_falling() -> void:
	var plant := _spawn("revette", Vector2(19.9, 10))
	plant.island.drop_inset = 2.0
	plant.state = Plant.State.PANIC
	plant.set_threat(Vector2(15, 10), Vector2(1, 0))
	plant.step(DT)
	assert_eq(plant.state, Plant.State.ESCAPED, "escapes at the walkable edge")
	var start_x := plant.position.x
	while plant.fall_travel() < 2.0 - 0.1:
		plant.step(DT)
		assert_near(plant.position.y, 0.0, 0.0001, "stays on the ground before the visible edge")
	assert_true(plant.position.x > start_x + 1.8, "ran outward (east)")
	assert_false(plant.is_queued_for_deletion(), "not freed while running")
	for i in 20:
		plant.step(DT)
	assert_true(plant.fall_travel() > 2.0, "passed the visible edge")
	assert_true(plant.position.y < 0.0, "drops once past the visible edge")
	_steps(plant, int(1.0 / DT) + 2)
	assert_true(plant.is_queued_for_deletion(), "freed about 1 s after the drop")
	_cleanup()

func test_calm_down_resets_panic() -> void:
	var plant := _spawn("revette", Vector2(10, 10))
	plant.state = Plant.State.FLEE
	plant.set_threat(Vector2(10 + Plant.CALM_DISTANCE + 5.0, 10), Vector2(-1, 0))
	_steps(plant, int((Plant.CALM_DURATION + 0.2) / DT))
	assert_eq(plant.state, Plant.State.WANDER, "back to wander after calm duration")
	assert_near(plant.panic_time(), 0.0, 0.0001, "panic counter reset")
	_cleanup()

func test_effective_speed() -> void:
	var plant := _spawn("nostalgerbe", Vector2(10, 10))
	plant.speed_multiplier = 1.5
	plant.state = Plant.State.FLEE
	# Close (< 4 m) so the zigzag never freezes.
	plant.set_threat(Vector2(13, 10), Vector2(-1, 0))
	plant.step(0.1)
	var expected := plant.species.base_speed * 1.5 * 0.1
	assert_near(_xz(plant).distance_to(Vector2(10, 10)), expected, 0.01, "base x multiplier x torpor")
	plant.hit_by_tool(ToolData.Effect.TORPOR)
	var before := _xz(plant)
	plant.step(0.1)
	assert_near(_xz(plant).distance_to(before), expected * 0.75, 0.01, "one dart slows by 25 %")
	_cleanup()

func test_asleep_plant_does_not_move() -> void:
	var plant := _spawn("revette", Vector2(10, 10))
	plant.state = Plant.State.FLEE
	plant.set_threat(Vector2(12, 10), Vector2(-1, 0))
	for i in 3:
		plant.hit_by_tool(ToolData.Effect.TORPOR)
	_steps(plant, 30)
	assert_near(_xz(plant).distance_to(Vector2(10, 10)), 0.0, 0.0001, "asleep: no motion")
	_cleanup()

func test_darter_pauses() -> void:
	var plant := _spawn("revette", Vector2(10, 10))
	plant.state = Plant.State.FLEE
	plant.set_threat(Vector2(12, 10), Vector2(-1, 0))
	_steps(plant, int(1.3 / DT))
	var before := _xz(plant)
	plant.step(0.2)
	assert_near(_xz(plant).distance_to(before), 0.0, 0.0001, "pause after a 1.2 s sprint")
	_cleanup()

func test_zigzag_freezes_out_of_cone() -> void:
	var plant := _spawn("nostalgerbe", Vector2(10, 10))
	plant.state = Plant.State.FLEE
	# Heroine 4.5 m away, aiming the other way.
	plant.set_threat(Vector2(14.5, 10), Vector2(1, 0))
	plant.step(0.1)
	assert_near(_xz(plant).distance_to(Vector2(10, 10)), 0.0, 0.0001, "frozen outside the cone")
	plant.set_threat(Vector2(14.5, 10), Vector2(-1, 0))
	plant.step(0.1)
	assert_true(_xz(plant).distance_to(Vector2(10, 10)) > 0.1, "moves inside the cone")
	_cleanup()

func test_burrower_cycle() -> void:
	var plant := _spawn("timidelle", Vector2(10, 10))
	var island := _square()
	plant.state = Plant.State.FLEE
	plant.set_threat(Vector2(12, 10), Vector2(-1, 0))
	plant.step(DT)
	assert_eq(plant.state, Plant.State.BURROWED, "burrows when heroine < 4 m")
	assert_false(plant.get_node("Visual").visible, "invisible while burrowed")
	_steps(plant, int(1.25 / DT))
	assert_eq(plant.state, Plant.State.EMERGING, "emerges after 1.2 s")
	assert_true(plant.get_node("Visual").visible, "visible when emerging")
	var d := _xz(plant).distance_to(Vector2(10, 10))
	assert_true(d >= 3.99 and d <= 6.01, "emerges 4-6 m away (%s)" % d)
	assert_true(island.contains(_xz(plant)), "emerges inside the island")
	plant.set_threat(Vector2(-50, -50), Vector2(1, 0))
	_steps(plant, int(1.05 / DT))
	assert_eq(plant.state, Plant.State.FLEE, "back to flee after 1 s")
	_cleanup()

func test_stalker_hits_heroine() -> void:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar hits: int = 0\nfunc take_nightmare_hit(_from: Variant = null) -> bool:\n\thits += 1\n\treturn true\n"
	script.reload()
	var heroine := Node3D.new()
	heroine.set_script(script)
	heroine.add_to_group("heroine")
	var plant := _spawn("ronce_angoisse", Vector2(10, 10))
	_root.add_child(heroine)
	plant.set_threat(Vector2(13, 10), Vector2(-1, 0))
	plant.step(1.0)
	assert_true(plant.position.x > 10.0, "seeks the heroine")
	assert_eq(plant.state, Plant.State.WANDER, "stalker never flees")
	assert_eq(heroine.get("hits"), 0, "no hit from afar")
	heroine.position = Vector3(plant.position.x + 0.5, 0, 10)
	plant.set_threat(Vector2(plant.position.x + 0.5, 10), Vector2(-1, 0))
	plant.step(DT)
	assert_true(int(heroine.get("hits")) >= 1, "contact calls take_nightmare_hit")
	_cleanup()

func test_stalker_stuns_after_accepted_hit() -> void:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar hits: int = 0\nvar from: Vector2\nfunc take_nightmare_hit(p: Variant = null) -> bool:\n\thits += 1\n\tfrom = p\n\treturn true\n"
	script.reload()
	var heroine := Node3D.new()
	heroine.set_script(script)
	heroine.add_to_group("heroine")
	var plant := _spawn("ronce_angoisse", Vector2(10, 10))
	_root.add_child(heroine)
	heroine.position = Vector3(10.5, 0, 10)
	plant.set_threat(Vector2(10.5, 10), Vector2(-1, 0))
	plant.step(DT)
	assert_eq(heroine.get("hits"), 1, "first contact hits")
	assert_true(heroine.get("from").distance_to(Vector2(10, 10)) < 0.1, "hit carries the Ronce position")
	assert_true(plant.is_stunned(), "stunned after an accepted hit")
	var pos := _xz(plant)
	_steps(plant, int(0.9 / DT))
	assert_eq(heroine.get("hits"), 1, "no chained hit while stunned")
	assert_true(_xz(plant).distance_to(pos) < 0.001, "stunned Ronce stays still")
	heroine.position = Vector3(18, 0, 18)
	plant.set_threat(Vector2(18, 18), Vector2(-1, 0))
	_steps(plant, int(0.2 / DT))
	assert_false(plant.is_stunned(), "stun ends after ~1 s")
	heroine.position = Vector3(plant.position.x + 0.3, 0, plant.position.z)
	plant.set_threat(_xz(plant) + Vector2(0.3, 0), Vector2(-1, 0))
	plant.step(DT)
	assert_eq(heroine.get("hits"), 2, "contact can hit again after the stun")
	_cleanup()

func test_wander_targets_avoid_obstacles() -> void:
	var plant := _spawn("revette", Vector2(4, 10))
	var shape := _square()
	shape.obstacles = PackedVector3Array([Vector3(8, 10, 3), Vector3(1.5, 10, 1)])
	plant.island = shape
	var checked := 0
	for i in 1200:
		plant.step(DT)
		if plant._wander_has_target:
			checked += 1
			assert_true(shape.is_clear(plant._wander_target, Plant.OBSTACLE_MARGIN - 0.001),
					"wander target clear of obstacles %s" % plant._wander_target)
			assert_true(shape.contains(plant._wander_target), "wander target on the island")
	assert_true(checked > 0, "wander targets were picked")
	_cleanup()

func test_emerge_avoids_obstacles() -> void:
	var plant := _spawn("revette", Vector2(10, 10))
	var shape := _square()
	shape.obstacles = PackedVector3Array([Vector3(10, 10, 3)])
	plant.island = shape
	plant.state = Plant.State.BURROWED
	plant.set_threat(Vector2(9, 10), Vector2(1, 0))
	_steps(plant, int(1.25 / DT))
	assert_eq(plant.state, Plant.State.EMERGING, "emerged")
	assert_true(shape.is_clear(_xz(plant), Plant.OBSTACLE_MARGIN - 0.001), "emerges outside the obstacle")
	_cleanup()

func test_stalker_without_heroine_is_safe() -> void:
	var plant := _spawn("ronce_angoisse", Vector2(10, 10))
	plant.set_threat(Vector2(10.3, 10), Vector2(-1, 0))
	_steps(plant, 10)
	assert_eq(plant.state, Plant.State.WANDER, "no error without a heroine")
	_cleanup()

func test_set_glow_drives_emission() -> void:
	var a := _spawn("revette")
	var b := _spawn("revette")
	a.set_glow(1.0)
	var lit := 0
	for node in a.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
		var mat := (node as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		if mat != null and mat.emission_enabled and mat.emission_energy_multiplier > PlantModelVisual.LIGHT_LIFT + 0.001:
			lit += 1
	assert_true(lit > 0, "glow lights the visual")
	var leaked := false
	for node in b.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
		var mat := (node as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		if mat != null and mat.emission_enabled and mat.emission_energy_multiplier > PlantModelVisual.LIGHT_LIFT + 0.001:
			leaked = true
	assert_false(leaked, "materials are per plant")
	_cleanup()

func test_startle_only_while_fleeing() -> void:
	var plant := _spawn("revette")
	plant.startle()
	assert_false(plant.is_startled(), "no startle while wandering")
	plant.state = Plant.State.FLEE
	plant.startle()
	assert_true(plant.is_startled(), "startled while fleeing")
	plant.set_threat(Vector2(5, 10), Vector2(1, 0))
	_steps(plant, 40)
	assert_true(plant.is_startled(), "still startled before 0.8 s")
	_steps(plant, 20)
	assert_false(plant.is_startled(), "startle ends after 0.8 s")
	_cleanup()

func test_glow_set_before_setup_is_applied() -> void:
	_root = Node3D.new()
	tree.root.add_child(_root)
	var plant := (load(PLANT_SCENE) as PackedScene).instantiate() as Plant
	_root.add_child(plant)
	plant.set_glow(0.5)
	plant.setup(load("res://data/species/revette.tres") as PlantSpecies, _square(), 1.0)
	var lit := 0
	var total := 0
	for node in plant.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
		var mat := (node as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		if mat == null:
			continue
		total += 1
		if mat.emission_enabled and is_equal_approx(mat.emission_energy_multiplier, 0.5 * Plant.GLOW_ENERGY):
			lit += 1
	assert_true(total > 0, "visual has materials")
	assert_eq(lit, total, "glow stored before setup is reapplied to the built visual")
	_cleanup()
