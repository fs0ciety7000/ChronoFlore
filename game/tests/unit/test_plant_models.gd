extends "res://tests/test_case.gd"
## Hand-made plant models (game/assets/custom/plants/build_plants.py): animations, budget, state.

const SPECIES_IDS: Array[String] = ["revette", "nostalgerbe", "timidelle", "ronce_angoisse", "calinette", "souffloine",
	"melancolys", "lumiole", "croque_colere", "lierre_jalousie", "ortie_regret", "champi_panique"]
const HOSTILE_IDS: Array[String] = ["ronce_angoisse", "croque_colere", "lierre_jalousie", "ortie_regret", "champi_panique"]
const PLANT_SCENE := "res://scenes/plants/plant.tscn"
const MIN_TRIS := 800
const MAX_TRIS := 2500

var _root: Node3D

func _species(id: String) -> PlantSpecies:
	return load("res://data/species/%s.tres" % id) as PlantSpecies

func _triangles(visual: Node) -> int:
	var tris := 0
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3 if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return tris

func _spawn(id: String) -> Plant:
	if _root == null:
		_root = Node3D.new()
		tree.root.add_child(_root)
	var plant := (load(PLANT_SCENE) as PackedScene).instantiate() as Plant
	_root.add_child(plant)
	var shape := IslandShape.new()
	shape.outline = PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(20, 20), Vector2(0, 20)])
	plant.setup(_species(id), shape, 1.0)
	plant.position = Vector3(10, 0, 10)
	return plant

func _model(plant: Plant) -> PlantModelVisual:
	var holder := plant.get_node("Visual")
	return holder.get_child(0) as PlantModelVisual if holder.get_child_count() > 0 else null

func _cleanup() -> void:
	if _root != null:
		_root.free()
		_root = null

func test_each_species_model_has_animations() -> void:
	for id in SPECIES_IDS:
		var species := _species(id)
		assert_true(species.visual_scene != null, "%s has a visual scene" % id)
		if species.visual_scene == null:
			continue
		var v := species.visual_scene.instantiate()
		tree.root.add_child(v)
		assert_true(v is PlantModelVisual, "%s visual is a PlantModelVisual" % id)
		var ap: AnimationPlayer = v.call("animation_player") if v.has_method("animation_player") else null
		assert_true(ap != null, "%s has an AnimationPlayer" % id)
		if ap == null:
			v.free()
			continue
		var names: Array[String] = ["Idle", "Move", "Sleep", "Caught"]
		if id in HOSTILE_IDS:
			names.append("Attack")
		for anim_name in names:
			assert_true(ap.has_animation(anim_name), "%s has %s" % [id, anim_name])
		if ap.has_animation("Idle") and ap.has_animation("Move"):
			assert_eq(ap.get_animation("Idle").loop_mode, Animation.LOOP_LINEAR, "%s Idle loops" % id)
			assert_eq(ap.get_animation("Move").loop_mode, Animation.LOOP_LINEAR, "%s Move loops" % id)
		if ap.has_animation("Caught"):
			assert_eq(ap.get_animation("Caught").loop_mode, Animation.LOOP_NONE, "%s Caught is one-shot" % id)
		var tris := _triangles(v)
		assert_true(tris >= MIN_TRIS and tris <= MAX_TRIS, "%s has %d triangles (800..2500)" % [id, tris])
		v.free()

func test_model_materials_are_named_with_base_colours() -> void:
	for id in SPECIES_IDS:
		var v := _species(id).visual_scene.instantiate()
		var named := 0
		var total := 0
		for node in v.find_children("*", "MeshInstance3D", true, false):
			var mesh := (node as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var mat := mesh.surface_get_material(s) as StandardMaterial3D
				total += 1
				if mat != null and mat.resource_name != "" and not mat.vertex_color_use_as_albedo:
					named += 1
		assert_true(total >= 4, "%s has several materials" % id)
		assert_eq(named, total, "%s materials are named, without vertex colours" % id)
		v.free()

func test_plant_state_drives_model_animation() -> void:
	var plant := _spawn("revette")
	var model := _model(plant)
	assert_true(model != null, "plant visual is a PlantModelVisual")
	if model == null:
		_cleanup()
		return
	var ap := model.animation_player()
	assert_eq(ap.current_animation, "Idle", "wandering plays Idle")
	plant.state = Plant.State.ALERT
	assert_eq(ap.current_animation, "Idle", "alert plays Idle")
	plant.state = Plant.State.FLEE
	assert_eq(ap.current_animation, "Move", "fleeing plays Move")
	plant.state = Plant.State.PANIC
	assert_eq(ap.current_animation, "Move", "panic plays Move")
	for i in 3:
		plant.torpor.add_dart()
	plant.step(1.0 / 60.0)
	assert_true(plant.torpor.is_asleep(), "three darts put it to sleep")
	assert_eq(ap.current_animation, "Sleep", "asleep plays Sleep")
	assert_true(plant.hit_by_tool(ToolData.Effect.CAPTURE), "captured asleep")
	assert_eq(ap.current_animation, "Caught", "captured plays Caught")
	_cleanup()

func test_model_play_state_mapping() -> void:
	var v := _species("ronce_angoisse").visual_scene.instantiate() as PlantModelVisual
	tree.root.add_child(v)
	var ap := v.animation_player()
	v.play_state(Plant.State.WANDER, false)
	assert_eq(ap.current_animation, "Idle", "WANDER -> Idle")
	v.play_state(Plant.State.FLEE, false)
	assert_eq(ap.current_animation, "Move", "FLEE -> Move")
	v.play_state(Plant.State.WANDER, true)
	assert_eq(ap.current_animation, "Sleep", "asleep -> Sleep")
	v.play_state(Plant.State.CAPTURED, true)
	assert_eq(ap.current_animation, "Caught", "CAPTURED -> Caught")
	v.free()

func test_model_glow_keeps_light_lift() -> void:
	var v := _species("timidelle").visual_scene.instantiate() as PlantModelVisual
	tree.root.add_child(v)
	v.set_glow(0.0)
	var mats := v.materials()
	assert_true(mats.size() >= 4, "per-instance materials collected")
	for mat in mats:
		assert_true(mat.emission_enabled, "light lift keeps emission on")
		assert_near(mat.emission_energy_multiplier, PlantModelVisual.LIGHT_LIFT, 0.001, "lift 0.2 at glow 0")
	v.set_glow(1.0)
	for mat in mats:
		assert_near(mat.emission_energy_multiplier, Plant.GLOW_ENERGY, 0.001, "full glow")
	v.free()

func test_lumiole_glow_parts_keep_their_light() -> void:
	var v := _species("lumiole").visual_scene.instantiate() as PlantModelVisual
	tree.root.add_child(v)
	v.set_glow(0.0)
	var glow_parts := 0
	for mat in v.materials():
		if mat.resource_name.begins_with("Glow"):
			glow_parts += 1
			assert_true(mat.emission_energy_multiplier > PlantModelVisual.LIGHT_LIFT + 0.1,
				"%s keeps its own glow by day" % mat.resource_name)
	assert_true(glow_parts >= 2, "lumiole has glowing parts (bulb, fireflies)")
	var lights := v.find_children("*", "OmniLight3D", true, false)
	assert_eq(lights.size(), 1, "lumiole carries a small light")
	if lights.size() == 1:
		var day := (lights[0] as OmniLight3D).light_energy
		v.set_glow(1.0)
		assert_true((lights[0] as OmniLight3D).light_energy > day, "its light grows at night")
	v.free()

func test_night_glow_keeps_hue_and_adds_rim() -> void:
	# Night readability: the glow is a deeper tint of the albedo (not a wash towards white) and a
	# soft rim outlines the model; by day the materials are untouched.
	var v := _species("revette").visual_scene.instantiate() as PlantModelVisual
	tree.root.add_child(v)
	v.set_glow(0.0)
	for mat in v.materials():
		assert_true(mat.emission.is_equal_approx(mat.albedo_color), "%s day emission is the albedo" % mat.resource_name)
		assert_false(mat.rim_enabled, "%s no rim by day" % mat.resource_name)
	v.set_glow(1.0)
	var deeper := 0
	for mat in v.materials():
		assert_true(mat.rim_enabled and mat.rim > 0.0, "%s rim at night" % mat.resource_name)
		if mat.albedo_color.s > 0.1:
			assert_near(mat.emission.h, mat.albedo_color.h, 0.02, "%s keeps its hue" % mat.resource_name)
			if mat.emission.s > mat.albedo_color.s + 0.05:
				deeper += 1
	assert_true(deeper >= 4, "night glow is a deeper tint (%d materials)" % deeper)
	v.free()
