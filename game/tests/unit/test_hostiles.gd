extends "res://tests/test_case.gd"
## Task B3: hostile plants (Ronce, Croque-Colère, Lierre-Jalousie, Ortie-Regret, Champi-Panique):
## capture only asleep, telegraphed attacks, spawn hours.

const PLANT_SCENE := "res://scenes/plants/plant.tscn"
const HEROINE_SCENE := preload("res://scenes/heroine/heroine.tscn")
const DT := 1.0 / 60.0
const HOSTILE_IDS: Array[String] = ["ronce_angoisse", "croque_colere", "lierre_jalousie", "ortie_regret",
	"champi_panique"]

var _root: Node3D

func _square() -> IslandShape:
	var s := IslandShape.new()
	s.outline = PackedVector2Array([Vector2(0, 0), Vector2(30, 0), Vector2(30, 30), Vector2(0, 30)])
	return s

func _species(id: String) -> PlantSpecies:
	return load("res://data/species/%s.tres" % id) as PlantSpecies

func _ensure_root() -> void:
	if _root == null:
		_root = Node3D.new()
		tree.root.add_child(_root)

func _spawn(species_id: String, at: Vector2) -> Plant:
	_ensure_root()
	var plant := (load(PLANT_SCENE) as PackedScene).instantiate() as Plant
	_root.add_child(plant)
	plant.setup(_species(species_id), _square(), 1.0)
	plant.position = Vector3(at.x, 0.0, at.y)
	return plant

## A real heroine (group "heroine") with 5 petals, standing at `at`.
func _heroine(at: Vector2) -> Heroine:
	_ensure_root()
	var h := HEROINE_SCENE.instantiate() as Heroine
	_root.add_child(h)
	await tree.process_frame
	h.lucidity = Lucidity.new(5)
	h.island = _square()
	h.global_position = Vector3(at.x, 0.0, at.y)
	return h

func _xz(node: Node3D) -> Vector2:
	return Vector2(node.position.x, node.position.z)

func _cleanup() -> void:
	if _root != null:
		_root.free()
		_root = null

## Croque's charge lane while it is shown (wind-up and charge), or null.
func _lane(plant: Plant) -> GroundMark:
	for child in plant.get_children():
		if child is GroundMark and String(child.name).begins_with("ChargeLane") and not child.is_queued_for_deletion():
			return child
	return null

func _sleep(plant: Plant) -> void:
	for i in Torpor.SLEEP_CHARGES:
		plant.hit_by_tool(ToolData.Effect.TORPOR)

# --- capture asleep (Review Focus 1) -----------------------------------------------------------

func test_hostile_capturable_only_asleep() -> void:
	for id in HOSTILE_IDS:
		var plant := _spawn(id, Vector2(10, 10))
		assert_true(plant.species.hostile, "%s is hostile" % id)
		assert_eq(plant.species.minutes_reward(), PlantSpecies.HOSTILE_REWARD_MINUTES, "%s gives 40 min" % id)
		assert_eq(PlantSpecies.HOSTILE_REWARD_MINUTES, 40, "hostile reward is 40")
		assert_false(plant.hit_by_tool(ToolData.Effect.CAPTURE), "%s awake: net fails" % id)
		plant.hit_by_tool(ToolData.Effect.TORPOR)
		plant.hit_by_tool(ToolData.Effect.TORPOR)
		assert_false(plant.hit_by_tool(ToolData.Effect.CAPTURE), "%s with 2 darts: net still fails" % id)
		plant.hit_by_tool(ToolData.Effect.PIN)
		assert_false(plant.hit_by_tool(ToolData.Effect.CAPTURE), "%s pinned but awake: net fails" % id)
		plant.hit_by_tool(ToolData.Effect.TORPOR)
		assert_true(plant.torpor.is_asleep(), "%s asleep after 3 darts" % id)
		var got: Array[int] = [0]
		plant.captured.connect(func(_p: Plant) -> void: got[0] += 1)
		assert_true(plant.hit_by_tool(ToolData.Effect.CAPTURE), "%s asleep: net captures" % id)
		assert_eq(plant.state, Plant.State.CAPTURED, "%s captured" % id)
		assert_eq(got[0], 1, "%s captured emitted once" % id)
		# Wakes up in the same frame, before the net: no capture "on waking".
		var other := _spawn(id, Vector2(20, 20))
		_sleep(other)
		other.step(Torpor.SLEEP_DURATION - 0.01)
		assert_true(other.torpor.is_asleep(), "%s still asleep just before waking" % id)
		other.step(0.02)
		assert_false(other.hit_by_tool(ToolData.Effect.CAPTURE), "%s woke before the net: capture fails" % id)
		assert_true(other.state != Plant.State.CAPTURED, "%s not captured on waking" % id)
	_cleanup()

func test_gentle_plants_are_not_hostile() -> void:
	for id in ["revette", "nostalgerbe", "timidelle", "calinette", "souffloine", "melancolys", "lumiole"]:
		assert_false(_species(id).hostile, "%s is gentle" % id)

func test_asleep_hostile_does_not_hit() -> void:
	var heroine := await _heroine(Vector2(10.5, 10))
	var plant := _spawn("ronce_angoisse", Vector2(10, 10))
	_sleep(plant)
	plant.set_threat(_xz(heroine), Vector2(-1, 0))
	plant.step(DT)
	assert_eq(heroine.lucidity.petals, 5, "a sleeping Ronce does not hurt")
	_cleanup()

# --- Ronce non-regression ----------------------------------------------------------------------

func test_ronce_still_works() -> void:
	var ronce := _species("ronce_angoisse")
	assert_eq(ronce.behavior, PlantSpecies.Behavior.STALKER, "ronce stalks")
	assert_near(ronce.min_hour, 0.0, 1e-6, "ronce from 0 h")
	var heroine := await _heroine(Vector2(13, 10))
	var plant := _spawn("ronce_angoisse", Vector2(10, 10))
	for i in 30:
		plant.set_threat(_xz(heroine), Vector2(-1, 0))
		plant.step(DT)
	assert_true(plant.position.x > 10.3, "creeps towards the heroine")
	assert_eq(plant.state, Plant.State.WANDER, "never flees")
	plant.position = Vector3(12.5, 0, 10)
	plant.set_threat(_xz(heroine), Vector2(-1, 0))
	plant.step(DT)
	assert_eq(heroine.lucidity.petals, 4, "contact costs a petal")
	assert_true(heroine.is_knocked_back(), "contact knocks the heroine back")
	assert_true(plant.is_stunned(), "ronce stunned 1 s after its hit")
	_cleanup()

# --- spawning ----------------------------------------------------------------------------------

func test_eligible_hostiles_by_hour() -> void:
	var c := load("res://data/catalog.tres") as GameCatalog
	var ids := func(list: Array[PlantSpecies]) -> Array:
		var out: Array = []
		for s in list:
			out.append(s.id)
		return out
	assert_eq(ids.call(SpawnRules.eligible_hostiles(c, 0.0)), [&"ronce_angoisse"], "0 h: Ronce only")
	assert_eq(ids.call(SpawnRules.eligible_hostiles(c, 1.99)), [&"ronce_angoisse"], "Croque not before 2 h")
	assert_eq(ids.call(SpawnRules.eligible_hostiles(c, 2.0)), [&"ronce_angoisse", &"croque_colere"], "2 h: + Croque")
	assert_eq(ids.call(SpawnRules.eligible_hostiles(c, 3.0)), [&"ronce_angoisse", &"croque_colere", &"lierre_jalousie"],
		"3 h: + Lierre")
	assert_eq(ids.call(SpawnRules.eligible_hostiles(c, 4.0)).back(), &"ortie_regret", "4 h: + Ortie")
	assert_eq(ids.call(SpawnRules.eligible_hostiles(c, 3.99)).has(&"ortie_regret"), false, "Ortie not before 4 h")
	assert_eq(ids.call(SpawnRules.eligible_hostiles(c, 5.0)), [&"ronce_angoisse", &"croque_colere", &"lierre_jalousie",
		&"ortie_regret", &"champi_panique"], "5 h: all five")
	assert_false(ids.call(SpawnRules.eligible_hostiles(c, 4.99)).has(&"champi_panique"), "Champi not before 5 h")
	for s in SpawnRules.eligible_capturables(c, 8.0):
		assert_false(s.hostile, "%s: gentle list has no hostile" % s.id)

# --- Croque-Colère (CHARGER) -------------------------------------------------------------------

func test_charger_telegraphs_then_charges() -> void:
	var croque := _species("croque_colere")
	assert_eq(croque.behavior, PlantSpecies.Behavior.CHARGER, "croque charges")
	assert_true(croque.hostile, "croque is hostile")
	var plant := _spawn("croque_colere", Vector2(10, 10))
	var threat := Vector2(14, 10)
	var frames := 0
	while not plant.is_telegraphing() and frames < 240:
		plant.set_threat(threat, Vector2(-1, 0))
		plant.step(DT)
		frames += 1
	assert_true(plant.is_telegraphing(), "winds up when the heroine is within 6 m")
	assert_true(plant.telegraph_mark() != null and plant.telegraph_mark().visible, "lane shown on the ground")
	var start := _xz(plant)
	threat = Vector2(14, 16) # the heroine side-steps: the charge keeps its line
	var still := 0
	while plant.is_telegraphing() and still < 240:
		plant.set_threat(threat, Vector2(-1, 0))
		plant.step(DT)
		still += 1
		if plant.is_telegraphing() and still % 10 == 0:
			assert_true(_xz(plant).distance_to(start) < 1e-4, "still during the wind-up")
	assert_true(still * DT >= Hazard.MIN_TELEGRAPH, "wind-up lasts >= 0.6 s (%.2f)" % (still * DT))
	assert_near(still * DT, BehaviorCharger.WINDUP_TIME, 2.0 * DT, "wind-up lasts 0.8 s")
	for i in int(0.2 / DT):
		plant.set_threat(threat, Vector2(-1, 0))
		plant.step(DT)
	var d := _xz(plant) - start
	assert_near(d.x, BehaviorCharger.CHARGE_SPEED * 0.2, 0.2, "charges at 9 m/s")
	assert_near(d.y, 0.0, 0.05, "along the line locked at the wind-up")
	for i in int(0.6 / DT):
		plant.set_threat(threat, Vector2(-1, 0))
		plant.step(DT)
	assert_false(plant.is_charging(), "charge over")
	assert_near((_xz(plant) - start).x, BehaviorCharger.CHARGE_DISTANCE, 0.3, "charge covers 6 m")
	_cleanup()

func test_charger_hit_stops_charge() -> void:
	var heroine := await _heroine(Vector2(13, 10))
	var plant := _spawn("croque_colere", Vector2(10, 10))
	var frames := 0
	while heroine.lucidity.petals == 5 and frames < 300:
		plant.set_threat(_xz(heroine), Vector2(-1, 0))
		plant.step(DT)
		frames += 1
	assert_eq(heroine.lucidity.petals, 4, "the charge costs one petal")
	assert_true(plant.is_stunned(), "croque stunned after its hit")
	assert_false(plant.is_charging(), "the charge stops on the hit")
	assert_false(plant.is_telegraphing(), "no wind-up while stunned")
	_cleanup()

func test_charger_contact_hurts_only_during_charge() -> void:
	# Ruling: Ronce and Champi hurt on contact (spec); Croque only through its telegraphed charge.
	var heroine := await _heroine(Vector2(10.6, 10))
	var plant := _spawn("croque_colere", Vector2(10, 10))
	var t := 0.0
	var lost_at := -1.0
	var lane_at := -1.0
	while t < 3.0 and lost_at < 0.0:
		plant.set_threat(_xz(heroine), Vector2(-1, 0))
		plant.step(DT)
		t += DT
		if lane_at < 0.0 and _lane(plant) != null:
			lane_at = t
		if heroine.lucidity.petals < 5:
			lost_at = t
	assert_true(lane_at > 0.0, "winds up next to the heroine")
	assert_true(lost_at > 0.0, "the charge hits")
	assert_true(lost_at - lane_at >= BehaviorCharger.WINDUP_TIME - 1e-4,
		"no petal before the wind-up is over (lane %.2f s, hit %.2f s)" % [lane_at, lost_at])
	assert_eq(heroine.lucidity.petals, 4, "one petal")
	_cleanup()

func test_charger_asleep_never_charges() -> void:
	var plant := _spawn("croque_colere", Vector2(10, 10))
	_sleep(plant)
	for i in 120:
		plant.set_threat(Vector2(13, 10), Vector2(-1, 0))
		plant.step(DT)
	assert_false(plant.is_telegraphing() or plant.is_charging(), "a sleeping croque does not attack")
	assert_true(_xz(plant).distance_to(Vector2(10, 10)) < 1e-4, "and does not move")
	_cleanup()

func test_charger_first_cooldown_after_waking() -> void:
	var plant := _spawn("croque_colere", Vector2(5, 5))
	for i in int(2.0 / DT): # heroine far away: the first cooldown runs out while stalking
		plant.set_threat(Vector2(28, 28), Vector2(-1, 0))
		plant.step(DT)
	assert_true(_lane(plant) == null, "no wind-up beyond 6 m")
	_sleep(plant)
	while plant.torpor.is_asleep():
		plant.set_threat(Vector2(28, 28), Vector2(-1, 0))
		plant.step(DT)
	assert_false(plant.torpor.is_asleep(), "awake again")
	var t := DT # it woke during the last tick above
	while _lane(plant) == null and t < 3.0:
		plant.set_threat(_xz(plant) + Vector2(4, 0), Vector2(-1, 0))
		plant.step(DT)
		t += DT
	assert_true(_lane(plant) != null, "winds up once awake")
	assert_true(t >= BehaviorCharger.FIRST_COOLDOWN - 1e-4, "waits the first cooldown after waking (%.2f s)" % t)
	_cleanup()

# --- Lierre-Jalousie (ROOT_TRAP) ---------------------------------------------------------------

func test_root_trap_casts_vine_ring_under_heroine() -> void:
	var lierre := _species("lierre_jalousie")
	assert_eq(lierre.behavior, PlantSpecies.Behavior.ROOT_TRAP, "lierre traps")
	var heroine := await _heroine(Vector2(15, 10))
	var plant := _spawn("lierre_jalousie", Vector2(10, 10))
	var rings: Array[Hazard] = []
	plant.hazard_spawned.connect(func(h: Hazard) -> void: rings.append(h))
	var t := 0.0
	while rings.is_empty() and t < 5.0:
		plant.set_threat(_xz(heroine), Vector2(-1, 0))
		plant.step(DT)
		t += DT
	assert_eq(rings.size(), 1, "casts a vine ring")
	if rings.is_empty():
		_cleanup()
		return
	var ring := rings[0]
	assert_true(ring is VineRing, "it is a vine ring")
	assert_true(ring.center_xz().distance_to(_xz(heroine)) < 0.05, "under the heroine")
	assert_near(ring.radius, VineRing.RADIUS, 1e-6, "radius 1.2 m")
	assert_near(VineRing.RADIUS, 1.2, 1e-6, "spec radius")
	assert_true(ring.telegraph_time >= 1.0 - 1e-6, "sign 1 s before the vines")
	for i in int(11.0 / DT):
		plant.set_threat(Vector2(15, 10), Vector2(-1, 0))
		plant.step(DT)
	assert_eq(rings.size(), 3, "one ring every 5 s (%d)" % rings.size())
	_cleanup()

# --- Ortie-Regret (SPITTER) --------------------------------------------------------------------

func test_spitter_shadow_precedes_impact() -> void:
	var ortie := _species("ortie_regret")
	assert_eq(ortie.behavior, PlantSpecies.Behavior.SPITTER, "ortie spits")
	var heroine := await _heroine(Vector2(15, 10))
	var plant := _spawn("ortie_regret", Vector2(10, 10))
	var thorns: Array[Hazard] = []
	var shown_at: Array[float] = []
	var struck_at: Array[float] = []
	var t := [0.0]
	plant.hazard_spawned.connect(func(h: Hazard) -> void:
		thorns.append(h)
		shown_at.append(t[0] if h.has_ground_mark() else INF)
		h.struck.connect(func(_target: Node3D) -> void: struck_at.append(t[0])))
	while struck_at.is_empty() and t[0] < 6.0:
		plant.set_threat(_xz(heroine), Vector2(-1, 0))
		plant.step(DT)
		for h in thorns:
			if is_instance_valid(h) and not h.is_queued_for_deletion():
				h.tick(DT)
		t[0] += DT
	assert_true(thorns.size() >= 1 and thorns[0] is ThornProjectile, "spits a thorn")
	assert_eq(struck_at.size(), 1, "the thorn lands on the standing heroine")
	if struck_at.size() == 1:
		assert_true(struck_at[0] - shown_at[0] >= Hazard.MIN_TELEGRAPH - 1e-6,
			"shadow shown %.2f s before the impact" % (struck_at[0] - shown_at[0]))
		assert_true(thorns[0].center_xz().distance_to(Vector2(15, 10)) < 0.05, "aimed where she stood")
	assert_eq(heroine.lucidity.petals, 4, "one petal")
	assert_true(_xz(plant).distance_to(Vector2(10, 10)) < 1e-4, "rooted: never moves")
	_cleanup()

func test_spitter_range_and_rhythm() -> void:
	var plant := _spawn("ortie_regret", Vector2(10, 10))
	var count: Array[int] = [0]
	plant.hazard_spawned.connect(func(_h: Hazard) -> void: count[0] += 1)
	for i in int(4.0 / DT):
		plant.set_threat(Vector2(10 + BehaviorSpitter.RANGE + 0.5, 10), Vector2(-1, 0))
		plant.step(DT)
	assert_eq(count[0], 0, "no thorn beyond 7 m")
	for i in int(7.0 / DT):
		plant.set_threat(Vector2(16, 10), Vector2(-1, 0))
		plant.step(DT)
	assert_eq(count[0], 3, "one thorn every 3 s within range (%d)" % count[0])
	assert_near(BehaviorSpitter.RANGE, 7.0, 1e-6, "range 7 m")
	assert_near(BehaviorSpitter.COOLDOWN, 3.0, 1e-6, "every 3 s")
	_cleanup()

func test_spitter_faces_heroine_at_rest() -> void:
	var plant := _spawn("ortie_regret", Vector2(10, 10))
	var visual := plant.get_node("Visual") as Node3D
	visual.rotation.y = 1.0
	for i in 30:
		plant.step(DT)
	assert_near(visual.rotation.y, 1.0, 1e-6, "no threat: keeps its heading (no snap to 0)")
	for i in 5:
		plant.set_threat(Vector2(15, 10), Vector2(-1, 0))
		plant.step(DT)
	assert_true(_xz(plant).distance_to(Vector2(10, 10)) < 1e-4, "rooted")
	assert_near(visual.rotation.y, PI / 2.0, 1e-4, "turns to the heroine without moving")
	_sleep(plant)
	for i in 5:
		plant.set_threat(Vector2(10, 15), Vector2(-1, 0))
		plant.step(DT)
	assert_near(visual.rotation.y, PI / 2.0, 1e-4, "asleep: stops tracking her")
	_cleanup()

# --- Champi-Panique (SPORE) --------------------------------------------------------------------

func test_spore_slows_no_petal() -> void:
	var champi := _species("champi_panique")
	assert_eq(champi.behavior, PlantSpecies.Behavior.SPORE, "champi bursts")
	var heroine := await _heroine(Vector2(14, 10))
	var plant := _spawn("champi_panique", Vector2(10, 10))
	var clouds: Array[Hazard] = []
	plant.hazard_spawned.connect(func(h: Hazard) -> void: clouds.append(h))
	var t := 0.0
	while clouds.is_empty() and t < 5.0:
		plant.set_threat(_xz(heroine), Vector2(-1, 0))
		plant.step(DT)
		t += DT
	assert_eq(clouds.size(), 1, "swells into a spore cloud")
	if clouds.is_empty():
		_cleanup()
		return
	var cloud := clouds[0]
	assert_true(cloud is SporeCloud, "it is a spore cloud")
	assert_true(plant.is_telegraphing(), "swells (telegraph) before bursting")
	assert_near(cloud.radius, 2.5, 1e-6, "cloud radius 2.5 m")
	assert_true(cloud.telegraph_time >= Hazard.MIN_TELEGRAPH, "swelling announced >= 0.6 s")
	var pos := _xz(plant)
	while cloud.is_telegraphing():
		plant.set_threat(_xz(heroine), Vector2(-1, 0))
		plant.step(DT)
		cloud.tick(DT)
	assert_true(_xz(plant).distance_to(pos) < 1e-4, "stands still while swelling")
	assert_true(heroine.is_slowed(), "the heroine is slowed in the cloud")
	assert_near(heroine.move_speed(), Heroine.SPEED * SporeCloud.SLOW_FACTOR, 1e-4, "to 50 %")
	assert_near(heroine.slowed_left(), SporeCloud.SLOW_TIME, 1e-4, "for 2 s")
	assert_eq(heroine.lucidity.petals, 5, "spores cost no petal")
	for i in 30:
		heroine.tick_status(DT)
		cloud.tick(DT)
	assert_near(heroine.slowed_left(), SporeCloud.SLOW_TIME, 1e-4, "staying in the cloud refreshes, never stacks")
	_cleanup()

func test_champi_contact_costs_petal() -> void:
	var heroine := await _heroine(Vector2(10.5, 10))
	var plant := _spawn("champi_panique", Vector2(10, 10))
	plant.set_threat(_xz(heroine), Vector2(-1, 0))
	plant.step(DT)
	assert_eq(heroine.lucidity.petals, 4, "direct contact costs a petal")
	_cleanup()
