extends "res://tests/test_case.gd"

const ISLAND_SCENE := "res://scenes/island/island.tscn"
const LIGHTING_SCENE := "res://scenes/env/night_lighting.tscn"

func test_island_instantiates() -> void:
	var island: Node = (load(ISLAND_SCENE) as PackedScene).instantiate()
	assert_true(island is Island, "root is Island")
	var shape: IslandShape = island.shape
	assert_true(shape != null, "shape assigned")
	if shape != null:
		assert_true(shape.outline.size() >= 8, "outline has >= 8 points")
		assert_true(shape.contains(Vector2.ZERO), "origin is walkable")
	assert_near(island.ground_height(), 0.0, 0.0001, "flat ground at y = 0")
	assert_true(island.is_in_group("island"), "in group island")
	island.free()

func test_island_meshes_use_named_materials() -> void:
	var island: Node = (load(ISLAND_SCENE) as PackedScene).instantiate()
	var meshes := island.find_children("*", "MeshInstance3D", true, false)
	assert_true(meshes.size() >= 5, "island and decor meshes present")
	var named := 0
	for node in meshes:
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as BaseMaterial3D
			if mat != null and not mat.resource_name.is_empty() and not mat.vertex_color_use_as_albedo:
				named += 1
	assert_true(named >= 10, "colours come from named materials (%d)" % named)
	island.free()

func test_walkable_meadow_is_large_and_pond_blocked() -> void:
	var island: Node = (load(ISLAND_SCENE) as PackedScene).instantiate()
	var shape: IslandShape = island.shape
	var rect := Rect2(shape.outline[0], Vector2.ZERO)
	for v in shape.outline:
		rect = rect.expand(v)
	assert_true(rect.size.x >= 30.0 and rect.size.y >= 30.0, "walkable area >= 30 x 30 m (%s)" % rect.size)
	assert_true(shape.outline.size() >= 12 and shape.outline.size() <= 24, "12-24 outline points")
	assert_eq(shape.obstacles.size(), 1, "pond obstacle")
	if shape.obstacles.size() == 1:
		var o := shape.obstacles[0]
		var pond := island.get_node("Pond") as StaticBody3D
		assert_near(pond.position.x, o.x, 0.01, "pond collider x matches obstacle")
		assert_near(pond.position.z, o.y, 0.01, "pond collider z matches obstacle")
		assert_true(shape.contains(Vector2(o.x, o.y)), "pond lies on the meadow")
	assert_true(shape.is_clear(shape.centroid(), 2.0), "heroine start is clear of the pond")
	island.free()

func test_enable_vertex_colors_duplicates_material() -> void:
	var original := StandardMaterial3D.new()
	var box := BoxMesh.new()
	box.material = original
	var mi := MeshInstance3D.new()
	mi.mesh = box
	var root := Node3D.new()
	root.add_child(mi)
	PolyforkUtil.enable_vertex_colors(root)
	var active := mi.get_active_material(0) as BaseMaterial3D
	assert_true(active != null and active.vertex_color_use_as_albedo, "override uses vertex colours")
	assert_false(original.vertex_color_use_as_albedo, "source material untouched")
	root.free()

func test_lighting_applies_palette() -> void:
	var lighting: Node = (load(LIGHTING_SCENE) as PackedScene).instantiate()
	tree.root.add_child(lighting)
	lighting.set_display_progress(1.0)
	var env: Environment = (lighting.get_node("WorldEnvironment") as WorldEnvironment).environment
	var bg := env.background_color
	var want := Color("f7c9d4")
	assert_eq(env.background_mode, Environment.BG_COLOR, "background mode colour")
	assert_near(bg.r, want.r, 0.01, "bg r")
	assert_near(bg.g, want.g, 0.01, "bg g")
	assert_near(bg.b, want.b, 0.01, "bg b")
	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_LINEAR, "linear tone mapping")
	var sun := lighting.get_node("Sun") as DirectionalLight3D
	assert_true(sun.shadow_enabled, "shadows on")
	assert_near(sun.light_energy, 0.17, 0.001, "sun energy at dawn")
	assert_near(sun.rotation_degrees.x, -20.0, 0.01, "sun pitch at dawn")
	assert_true(env.adjustment_enabled, "colour adjustments on")
	assert_near(env.adjustment_saturation, 1.05, 0.001, "dawn saturation")
	assert_true(env.fog_enabled, "dawn tint fog on")
	assert_near(env.fog_density, -log(1.0 - 0.2) / NightLighting.TINT_REFERENCE_DISTANCE, 0.0001, "tint density")
	lighting.set_display_progress(0.0)
	assert_false(env.fog_enabled, "no tint by day")
	lighting.queue_free()
	await tree.process_frame

func test_lighting_eases_towards_target_and_signals_glow() -> void:
	var lighting: Node = (load(LIGHTING_SCENE) as PackedScene).instantiate()
	tree.root.add_child(lighting)
	lighting.set_process(false)
	var glows: Array[float] = []
	lighting.glow_changed.connect(func(v: float) -> void: glows.append(v))
	lighting.set_display_progress(0.0)
	lighting.target_progress = 0.5
	lighting._process(0.1)
	var expected := lerpf(0.0, 0.5, 1.0 - exp(-1.5 * 0.1))
	assert_near(lighting.get_display_progress(), expected, 0.0001, "eases with exp factor")
	glows.clear()
	lighting.set_display_progress(0.5)
	assert_eq(glows.size(), 1, "glow change emitted once")
	if glows.size() == 1:
		assert_near(glows[0], 1.0, 0.0001, "glow value at midnight")
	lighting.set_display_progress(0.5001)
	assert_eq(glows.size(), 1, "no emit for tiny glow change")
	lighting.queue_free()
	await tree.process_frame
