extends "res://tests/test_case.gd"

var _root: Node3D

func _catalog() -> GameCatalog:
	return load("res://data/catalog.tres") as GameCatalog

func _belt() -> ToolBelt:
	if _root == null:
		_root = Node3D.new()
		tree.root.add_child(_root)
	var belt := ToolBelt.new()
	_root.add_child(belt)
	return belt

func _tool(id: StringName) -> ToolData:
	return _catalog().tool_by_id(id)

func _plant_at(x: float, z: float) -> Plant:
	var plant := (load("res://scenes/plants/plant.tscn") as PackedScene).instantiate() as Plant
	_root.add_child(plant)
	var island := IslandShape.new()
	island.outline = PackedVector2Array([Vector2(-20, -20), Vector2(20, -20), Vector2(20, 20), Vector2(-20, 20)])
	plant.setup(load("res://data/species/revette.tres") as PlantSpecies, island, 1.0)
	plant.position = Vector3(x, 0.0, z)
	return plant

func _find_projectile() -> Projectile:
	for c in tree.root.get_children():
		if c is Projectile:
			return c
	return null

func _cleanup() -> void:
	for c in tree.root.get_children():
		if c is Projectile or c is MuzzlePuff:
			c.free()
	if _root != null:
		_root.free()
		_root = null

func test_cycle_wraps() -> void:
	var belt := _belt()
	belt.set_tools([_tool(&"net"), _tool(&"tranquilizer")] as Array[ToolData])
	belt.cycle(1)
	assert_eq(belt.index, 1, "after one cycle")
	belt.cycle(1)
	assert_eq(belt.index, 0, "wraps to 0")
	belt.cycle(-1)
	assert_eq(belt.index, 1, "wraps backwards")
	_cleanup()

func test_cooldown() -> void:
	var belt := _belt()
	belt.set_tools([_tool(&"tranquilizer")] as Array[ToolData])
	assert_true(belt.try_use(Vector3.ZERO, Vector2(0, 1)), "first use")
	assert_false(belt.try_use(Vector3.ZERO, Vector2(0, 1)), "on cooldown")
	belt.tick(0.6)
	assert_true(belt.try_use(Vector3.ZERO, Vector2(0, 1)), "after cooldown")
	_cleanup()

func test_harpoon_absent_by_default() -> void:
	var belt := _belt()
	var catalog := _catalog()
	var ids := Herbarium.new().available_tools(catalog)
	var list: Array[ToolData] = []
	for id in ids:
		list.append(catalog.tool_by_id(id))
	belt.set_tools(list)
	assert_eq(belt.tools.size(), 2, "net and tranquilizer only")
	_cleanup()

func test_net_captures_slowed_plant() -> void:
	var belt := _belt()
	belt.set_tools([_tool(&"net")] as Array[ToolData])
	var plant := _plant_at(0.0, 1.5)
	plant.torpor.add_dart()
	plant.torpor.add_dart()
	var got: Array[int] = [0]
	plant.captured.connect(func(_p: Plant) -> void: got[0] += 1)
	assert_true(belt.try_use(Vector3.ZERO, Vector2(0, 1)), "net used")
	assert_eq(got[0], 1, "plant captured emitted")
	_cleanup()

func test_net_miss_startles_fleeing_plant() -> void:
	var belt := _belt()
	belt.set_tools([_tool(&"net")] as Array[ToolData])
	var plant := _plant_at(0.0, 1.5)
	assert_true(belt.try_use(Vector3.ZERO, Vector2(0, 1)), "net used")
	assert_true(plant.is_startled(), "missed plant is startled")
	_cleanup()

func test_net_ignores_plant_outside_cone() -> void:
	var belt := _belt()
	belt.set_tools([_tool(&"net")] as Array[ToolData])
	var plant := _plant_at(0.0, -1.5)
	plant.torpor.add_dart()
	plant.torpor.add_dart()
	var got: Array[int] = [0]
	plant.captured.connect(func(_p: Plant) -> void: got[0] += 1)
	belt.try_use(Vector3.ZERO, Vector2(0, 1))
	assert_eq(got[0], 0, "behind the heroine: not captured")
	_cleanup()

func test_dart_projectile_hits_plant() -> void:
	var belt := _belt()
	belt.set_tools([_tool(&"tranquilizer")] as Array[ToolData])
	var plant := _plant_at(0.0, 5.0)
	belt.try_use(Vector3.ZERO, Vector2(0, 1))
	var proj := _find_projectile()
	assert_true(proj != null, "projectile spawned")
	for i in 60:
		if is_instance_valid(proj) and not proj.is_queued_for_deletion():
			proj.step(1.0 / 60.0)
	assert_eq(plant.torpor.charges, 1, "dart hit adds a charge")
	assert_true(proj.is_queued_for_deletion(), "projectile consumed")
	_cleanup()

func test_projectile_expires_at_max_range() -> void:
	var belt := _belt()
	belt.set_tools([_tool(&"tranquilizer")] as Array[ToolData])
	belt.try_use(Vector3.ZERO, Vector2(0, 1))
	var proj := _find_projectile()
	for i in 120:
		if not proj.is_queued_for_deletion():
			proj.step(1.0 / 60.0)
	assert_true(proj.is_queued_for_deletion(), "removed after max range")
	_cleanup()

func test_projectile_ignores_burrowed_plant() -> void:
	var belt := _belt()
	belt.set_tools([_tool(&"tranquilizer")] as Array[ToolData])
	var plant := _plant_at(0.0, 3.0)
	plant.state = Plant.State.BURROWED
	belt.try_use(Vector3.ZERO, Vector2(0, 1))
	var proj := _find_projectile()
	for i in 30:
		proj.step(1.0 / 60.0)
	assert_eq(plant.torpor.charges, 0, "burrowed plant untouched")
	assert_false(proj.is_queued_for_deletion(), "projectile flies on")
	_cleanup()

func _children_of_type(script: Script) -> Array[Node]:
	var out: Array[Node] = []
	for c in tree.root.get_children():
		if is_instance_of(c, script):
			out.append(c)
	return out

func test_net_use_spawns_no_world_effect() -> void:
	var belt := _belt()
	belt.set_tools([_tool(&"net")] as Array[ToolData])
	var dir := Vector2(1, 0)
	assert_true(belt.try_use(Vector3(1, 0.5, 2), dir), "net used")
	assert_eq(_children_of_type(MuzzlePuff).size(), 0, "no muzzle puff for the net (its trail follows the hoop)")
	assert_eq(belt.last_use_dir, dir, "net use direction kept")
	_cleanup()

func test_dart_shot_spawns_a_muzzle_puff() -> void:
	var belt := _belt()
	belt.set_tools([_tool(&"tranquilizer")] as Array[ToolData])
	assert_true(belt.try_use(Vector3(0, 0.5, 0), Vector2(0, 1)), "dart fired")
	var puffs := _children_of_type(MuzzlePuff)
	assert_eq(puffs.size(), 1, "one muzzle puff")
	if puffs.size() == 1:
		var p := (puffs[0] as Node3D).position
		assert_near(p.z, ToolBelt.MUZZLE_OFFSET, 1e-4, "puff in front along the shot")
	assert_near(belt.last_use_dir.length(), 1.0, 1e-4, "shot direction kept")
	_cleanup()

func test_shot_direction_is_the_assisted_one() -> void:
	var belt := _belt()
	belt.set_tools([_tool(&"tranquilizer")] as Array[ToolData])
	var plant := _plant_at(1.0, 5.0) # ~11 deg off the aim: inside the assist cone
	belt.try_use(Vector3(0, 0.5, 0), Vector2(0, 1))
	assert_true(belt.last_use_dir.x > 0.01, "nudged toward the plant")
	plant.free()
	_cleanup()
