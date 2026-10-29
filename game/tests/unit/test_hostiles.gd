extends "res://tests/test_case.gd"
## Task B3: hostile plants (Ronce, Croque-Colère, Lierre-Jalousie, Ortie-Regret, Champi-Panique):
## capture only asleep, telegraphed attacks, spawn hours.

const PLANT_SCENE := "res://scenes/plants/plant.tscn"
const HEROINE_SCENE := preload("res://scenes/heroine/heroine.tscn")
const DT := 1.0 / 60.0

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

func _sleep(plant: Plant) -> void:
	for i in Torpor.SLEEP_CHARGES:
		plant.hit_by_tool(ToolData.Effect.TORPOR)

# --- capture asleep (Review Focus 1) -----------------------------------------------------------

func test_hostile_capturable_only_asleep() -> void:
	for id in ["ronce_angoisse"]:
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
	for s in SpawnRules.eligible_capturables(c, 8.0):
		assert_false(s.hostile, "%s: gentle list has no hostile" % s.id)
