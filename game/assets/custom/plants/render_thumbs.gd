extends SceneTree
## Renders the herbarium thumbnails (once, committed as PNG under thumbs/):
##   <id>.png      the species model on a transparent background
##   <id>_sil.png  the same shape as a flat silhouette, for pages not yet discovered
## Needs a real renderer (not --headless), from the repo root:
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path game --rendering-driver opengl3 \
##     --script res://assets/custom/plants/render_thumbs.gd

const OUT_DIR := "res://assets/custom/plants/thumbs"
const SIZE := 192
const SILHOUETTE := Color("#cfc6dc")
const PADDING := 1.08

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog: GameCatalog = load("res://data/catalog.tres")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for species in catalog.species:
		await _render(species)
	quit(0)

func _render(species: PlantSpecies) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#fff4e6")
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 0.9
	vp.add_child(sun)
	var model: Node3D = species.visual_scene.instantiate()
	vp.add_child(model)
	for i in 4:
		await process_frame
	var box := _aabb(model)
	var center := box.get_center()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(box.size.y, maxf(box.size.x, box.size.z)) * PADDING + 0.05
	vp.add_child(cam)
	cam.position = center + Vector3(0.9, 0.8, 1.5).normalized() * 4.0
	cam.look_at(center, Vector3.UP)
	cam.current = true
	for i in 4:
		await process_frame
	var img := vp.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, species.id]))
	var sil := img.duplicate() as Image
	for y in sil.get_height():
		for x in sil.get_width():
			var a := sil.get_pixel(x, y).a
			sil.set_pixel(x, y, Color(SILHOUETTE.r, SILHOUETTE.g, SILHOUETTE.b, a))
	sil.save_png(ProjectSettings.globalize_path("%s/%s_sil.png" % [OUT_DIR, species.id]))
	print("thumb ", species.id, " ", box)
	vp.queue_free()
	await process_frame

static func _aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D:
			var m := n as MeshInstance3D
			var b := m.global_transform * m.get_aabb()
			result = b if first else result.merge(b)
			first = false
	return result
