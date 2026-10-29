extends "res://tests/test_case.gd"
## Task B2: Câlinette (SHY_APPROACH), Souffloine (HOPPER), Mélancolys (POND_SEEKER), Lumiole (FLOATER).

const PLANT_SCENE := "res://scenes/plants/plant.tscn"
const DT := 1.0 / 60.0
## Test pond: centre (14, 10), radius 2, inside the 20 x 20 square.
const POND := Vector3(14, 10, 2)

var _root: Node3D

func _square(with_pond: bool = false) -> IslandShape:
	var s := IslandShape.new()
	s.outline = PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(20, 20), Vector2(0, 20)])
	if with_pond:
		s.obstacles = PackedVector3Array([POND])
	return s

func _species(id: String) -> PlantSpecies:
	return load("res://data/species/%s.tres" % id) as PlantSpecies

func _spawn(species_id: String, at: Vector2, island: IslandShape = null) -> Plant:
	if _root == null:
		_root = Node3D.new()
		tree.root.add_child(_root)
	var plant := (load(PLANT_SCENE) as PackedScene).instantiate() as Plant
	_root.add_child(plant)
	plant.setup(_species(species_id), island if island != null else _square(), 1.0)
	plant.position = Vector3(at.x, 0.0, at.y)
	return plant

func _xz(plant: Plant) -> Vector2:
	return Vector2(plant.position.x, plant.position.z)

func _cleanup() -> void:
	if _root != null:
		_root.free()
		_root = null

func _in_water(p: Vector2, island: IslandShape) -> bool:
	for w in island.water_zones():
		if p.distance_to(Vector2(w.x, w.y)) < w.z:
			return true
	return false

# --- Câlinette ---------------------------------------------------------------------------------

func test_calinette_approaches_then_hops_back() -> void:
	var heroine := Vector2(11.5, 10)
	var plant := _spawn("calinette", Vector2(8, 10))
	assert_eq(plant.species.behavior, PlantSpecies.Behavior.SHY_APPROACH, "calinette is a shy approacher")
	var start := _xz(plant).distance_to(heroine)
	var min_d := start
	var min_frame := -1
	var after_max := 0.0
	for i in 300:
		plant.set_threat(heroine, Vector2(-1, 0))
		plant.step(DT)
		var d := _xz(plant).distance_to(heroine)
		if d < min_d - 1e-4:
			min_d = d
			min_frame = i
		if min_frame >= 0 and i > min_frame:
			after_max = maxf(after_max, d)
	assert_true(min_frame > 0, "distance decreases (approach)")
	assert_near(min_d, BehaviorShyApproach.APPROACH_DISTANCE, 0.15, "approaches down to 2.5 m")
	assert_true(after_max - min_d > 3.0, "hop back moves it more than 3 m away (%.2f)" % (after_max - min_d))
	_cleanup()

func test_calinette_netted_during_approach_only() -> void:
	var heroine := Vector2(11.5, 10)
	var plant := _spawn("calinette", Vector2(8, 10))
	for i in 30: # alerted, now approaching
		plant.set_threat(heroine, Vector2(-1, 0))
		plant.step(DT)
	assert_true(plant.can_net_without_torpor(), "approach is the picking window")
	var other := _spawn("calinette", Vector2(8, 10))
	var hopped := false
	for i in 300:
		other.set_threat(heroine, Vector2(-1, 0))
		other.step(DT)
		if _xz(other).distance_to(heroine) > 5.0:
			hopped = true
			break
	assert_true(hopped, "the other one hopped back")
	assert_false(other.can_net_without_torpor(), "no free pick once it hopped back")
	assert_false(other.hit_by_tool(ToolData.Effect.CAPTURE), "net fails after the hop without darts")
	assert_true(plant.hit_by_tool(ToolData.Effect.CAPTURE), "net picks the approaching one without darts")
	_cleanup()

func test_calinette_panic_mid_hop_lands_and_faces_flight() -> void:
	# FLEE -> PANIC keeps the behavior: a panic during the hop must not leave her floating.
	var heroine := Vector2(11.5, 10)
	var plant := _spawn("calinette", Vector2(8, 10))
	var hopping := false
	for i in 300:
		plant.set_threat(heroine, Vector2(-1, 0))
		plant.step(DT)
		if plant.hover_height() > 0.0:
			hopping = true
			break
	assert_true(hopping, "mid-hop before the panic")
	plant.state = Plant.State.PANIC
	var before := _xz(plant)
	plant.set_threat(heroine, Vector2(-1, 0))
	plant.step(DT)
	assert_eq(plant.hover_height(), 0.0, "lands as soon as she panics")
	var motion := _xz(plant) - before
	assert_true(motion.length() > 0.0, "runs in PANIC")
	var visual := plant.get_node("Visual") as Node3D
	assert_near(visual.rotation.y, atan2(motion.x, motion.y), 1e-3, "faces her flight, not the heroine")
	for i in 60:
		plant.set_threat(heroine, Vector2(-1, 0))
		plant.step(DT)
	assert_eq(plant.hover_height(), 0.0, "stays on the ground in PANIC")
	_cleanup()

# --- Souffloine --------------------------------------------------------------------------------

func test_souffloine_uncatchable_airborne() -> void:
	var plant := _spawn("souffloine", Vector2(10, 10))
	assert_eq(plant.species.behavior, PlantSpecies.Behavior.HOPPER, "souffloine hops")
	var heroine := Vector2(12.5, 10)
	var got_air := false
	for i in 180:
		plant.set_threat(heroine, Vector2(-1, 0))
		plant.step(DT)
		if plant.is_airborne():
			got_air = true
			break
	assert_true(got_air, "souffloine leaves the ground")
	plant.hit_by_tool(ToolData.Effect.TORPOR) # darts still reach it
	plant.hit_by_tool(ToolData.Effect.TORPOR)
	assert_eq(plant.torpor.charges, 2, "darts hit an airborne souffloine")
	assert_false(plant.hit_by_tool(ToolData.Effect.CAPTURE), "net misses while airborne")
	assert_true(plant.state != Plant.State.CAPTURED, "not captured in the air")
	var air_frames := 0
	while plant.is_airborne() and air_frames < 200:
		plant.set_threat(heroine, Vector2(-1, 0))
		plant.step(DT)
		air_frames += 1
	assert_false(plant.is_airborne(), "lands")
	assert_true(plant.hit_by_tool(ToolData.Effect.CAPTURE), "net captures it on the ground")
	_cleanup()

func test_souffloine_hop_length_and_air_time() -> void:
	var plant := _spawn("souffloine", Vector2(8, 10))
	var heroine := Vector2(10.5, 10)
	var air := 0
	var took_off := Vector2.ZERO
	var landed := Vector2.ZERO
	for i in 240:
		plant.set_threat(heroine, Vector2(-1, 0))
		var was := plant.is_airborne()
		var before := _xz(plant)
		plant.step(DT)
		if plant.is_airborne() and not was:
			took_off = before
		if plant.is_airborne():
			air += 1
		elif was:
			landed = _xz(plant)
			break
	assert_near(float(air) * DT, BehaviorHopper.AIR_TIME, 0.05, "0.7 s in the air")
	assert_near(took_off.distance_to(landed), BehaviorHopper.HOP_DISTANCE, 0.2, "3 m hop")
	_cleanup()

func test_souffloine_never_leaves_island_unless_panic() -> void:
	# Review Focus 4: chased against the edge, every hop lands inside the outline.
	var island := _square()
	var plant := _spawn("souffloine", Vector2(1.0, 10), island)
	var hops := 0
	var ok := true
	for i in 420: # under panic_after
		var p := _xz(plant)
		plant.set_threat(p + Vector2(2.0, 0.3), Vector2(-1, 0))
		var was := plant.is_airborne()
		plant.step(DT)
		if plant.is_airborne() and not was:
			hops += 1
		if plant.state != Plant.State.PANIC and plant.state != Plant.State.ESCAPED:
			if not island.contains(_xz(plant)) or island.distance_to_edge(_xz(plant)) < Plant.EDGE_MARGIN - 0.01:
				ok = false
	assert_true(hops >= 3, "hopped several times (%d)" % hops)
	assert_true(ok, "never left the island while not panicked")
	assert_true(plant.state != Plant.State.ESCAPED, "did not escape")
	# In panic, the hop may carry it off the edge.
	plant.state = Plant.State.PANIC
	for i in 300:
		if plant.state == Plant.State.ESCAPED:
			break
		plant.set_threat(_xz(plant) + Vector2(2.0, 0.0), Vector2(-1, 0))
		plant.step(DT)
	assert_eq(plant.state, Plant.State.ESCAPED, "a panicked souffloine can hop off")
	_cleanup()

# --- Mélancolys --------------------------------------------------------------------------------

func test_island_exposes_the_pond_as_water() -> void:
	var real := load("res://data/island_shape.tres") as IslandShape
	assert_eq(real.water_zones().size(), 1, "the pond is the only water zone")
	assert_eq(real.water_zones(), real.obstacles, "water zones are the pond obstacle")

func test_melancolys_hides_in_pond_and_ignores_tools() -> void:
	var island := _square(true)
	var plant := _spawn("melancolys", Vector2(8, 10), island)
	assert_eq(plant.species.behavior, PlantSpecies.Behavior.POND_SEEKER, "melancolys seeks the pond")
	var heroine := Vector2(5, 10)
	var reached := -1
	for i in 600:
		plant.set_threat(heroine, Vector2(1, 0))
		plant.step(DT)
		if plant.is_hidden():
			reached = i
			break
	assert_true(reached > 0, "reaches the pond and hides")
	assert_true(_in_water(_xz(plant), island), "hidden in the water")
	assert_false(plant.hit_by_tool(ToolData.Effect.TORPOR), "dart ignored")
	assert_eq(plant.torpor.charges, 0, "no charge while hidden")
	plant.hit_by_tool(ToolData.Effect.PIN)
	assert_false(plant.torpor.is_pinned(), "harpoon ignored")
	plant.torpor.add_dart()
	plant.torpor.add_dart()
	assert_false(plant.hit_by_tool(ToolData.Effect.CAPTURE), "net ignored even when slowed")
	assert_true(plant.state != Plant.State.CAPTURED, "not captured in the water")
	assert_false(Projectile._can_hit(plant), "projectiles fly over the hidden lily")
	var hidden_frames := 1
	while plant.is_hidden() and hidden_frames < 600:
		plant.set_threat(heroine, Vector2(1, 0))
		plant.step(DT)
		hidden_frames += 1
	assert_near(float(hidden_frames) * DT, BehaviorPondSeeker.HIDE_DURATION, 0.05, "hidden 4 s")
	var p := _xz(plant)
	assert_false(_in_water(p, island), "emerges on dry land")
	assert_true(island.is_clear(p, Plant.OBSTACLE_MARGIN - 0.01), "emerges clear of the pond")
	assert_true(island.contains(p), "emerges on the island")
	_cleanup()

func test_melancolys_speed() -> void:
	var s := _species("melancolys")
	assert_near(s.base_speed, 2.2, 0.0001, "2.2 m/s")

func test_melancolys_never_spawns_in_water() -> void:
	# Review Focus 3: spawn points, the way to the pond and the way out never touch the water
	# or the heroine.
	var real := load("res://data/island_shape.tres") as IslandShape
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var dry := true
	for i in 500:
		if _in_water(real.random_point(rng, NightSession.SPAWN_MARGIN), real):
			dry = false
	assert_true(dry, "spawn points are never in the water")
	# Heroine waiting right on the shore point nearest the plant.
	var island := _square(true)
	var heroine := Vector2(POND.x - POND.z - Plant.OBSTACLE_MARGIN, POND.y)
	var plant := _spawn("melancolys", Vector2(8, 10), island)
	var min_gap := INF
	var hidden_at := -1
	var dry_walk := true
	for i in 900:
		plant.set_threat(heroine, Vector2(1, 0))
		plant.step(DT)
		if plant.is_hidden():
			hidden_at = i
			break
		min_gap = minf(min_gap, _xz(plant).distance_to(heroine))
		if _in_water(_xz(plant), island):
			dry_walk = false
	assert_true(hidden_at > 0, "still reaches the water around the heroine (not stuck)")
	assert_true(min_gap >= 1.0, "never walks through the heroine (closest %.2f m)" % min_gap)
	assert_true(dry_walk, "walks on dry land until it dives")
	# The heroine moves to the shore near the lily: it comes out away from her, on dry land.
	heroine = _shore_towards(_xz(plant))
	for i in 600:
		plant.set_threat(heroine, Vector2(1, 0))
		plant.step(DT)
		if not plant.is_hidden():
			break
	var out := _xz(plant)
	assert_false(plant.is_hidden(), "came out")
	assert_false(_in_water(out, island), "came out of the water")
	assert_true(island.is_clear(out, Plant.OBSTACLE_MARGIN - 0.01), "on the shore, clear of the pond")
	assert_true(out.distance_to(heroine) >= BehaviorPondSeeker.EMERGE_CLEARANCE - 0.01, "away from the heroine")
	_cleanup()

func _shore_towards(p: Vector2) -> Vector2:
	var c := Vector2(POND.x, POND.y)
	return c + (p - c).normalized() * (POND.z + Plant.OBSTACLE_MARGIN)

# --- Lumiole -----------------------------------------------------------------------------------

func test_lumiole_rare_reward_60() -> void:
	var s := _species("lumiole")
	assert_eq(s.rarity, PlantSpecies.Rarity.RARE, "lumiole is rare")
	assert_eq(s.minutes_reward(), 60, "+60 min")
	assert_near(s.base_speed, 6.0, 0.0001, "6 m/s")
	assert_eq(s.behavior, PlantSpecies.Behavior.FLOATER, "lumiole floats")
	var plant := _spawn("lumiole", Vector2(10, 10))
	assert_near(plant.hover_height(), BehaviorFloater.FLOAT_HEIGHT, 0.1, "floats at 0.8 m")
	assert_false(plant.is_airborne(), "floating stays within net reach")
	plant.hit_by_tool(ToolData.Effect.TORPOR)
	plant.hit_by_tool(ToolData.Effect.TORPOR)
	assert_true(plant.hit_by_tool(ToolData.Effect.CAPTURE), "the net reaches a floating lumiole")
	_cleanup()

func test_lumiole_flees_fast() -> void:
	var plant := _spawn("lumiole", Vector2(10, 10))
	plant.state = Plant.State.FLEE
	var start := _xz(plant)
	for i in 30:
		plant.set_threat(Vector2(8, 10), Vector2(1, 0))
		plant.step(DT)
	var travelled := _xz(plant).distance_to(start)
	assert_true(travelled > 6.0 * 0.5 * 0.85, "about 6 m/s (%.2f m in 0.5 s)" % travelled)
	_cleanup()

# --- spawn hours -------------------------------------------------------------------------------

func test_new_species_spawn_hours() -> void:
	var c := load("res://data/catalog.tres") as GameCatalog
	var hours := {&"calinette": 0.0, &"souffloine": 1.0, &"melancolys": 3.0, &"lumiole": 4.0}
	for id: StringName in hours:
		var s := c.species_by_id(id)
		assert_true(s != null, "%s in the catalog" % id)
		if s == null:
			continue
		var h: float = hours[id]
		assert_near(s.min_hour, h, 0.0001, "%s min_hour" % id)
		assert_true(s in SpawnRules.eligible_capturables(c, h), "%s eligible at %s h" % [id, h])
		if h > 0.0:
			assert_false(s in SpawnRules.eligible_capturables(c, h - 0.01), "%s not before %s h" % [id, h])
	var rarities := {&"calinette": PlantSpecies.Rarity.COMMON, &"souffloine": PlantSpecies.Rarity.UNCOMMON,
		&"melancolys": PlantSpecies.Rarity.UNCOMMON, &"lumiole": PlantSpecies.Rarity.RARE}
	for id: StringName in rarities:
		var s := c.species_by_id(id)
		if s != null:
			assert_eq(s.rarity, rarities[id], "%s rarity" % id)
			assert_true(s.capturable, "%s capturable" % id)
			assert_true(s.visual_scene != null, "%s has a visual" % id)
