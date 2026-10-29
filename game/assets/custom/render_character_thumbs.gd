extends SceneTree
## Renders the character-select thumbnails (once, committed as PNG):
##   heroine/thumb.png  the heroine alone
##   hero2/thumb.png    the hero alone
##   coop/thumb.png     both, side by side
## Hand tools are hidden.
## Transparent background (the card draws its own). Needs a real renderer, from the repo root:
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path game --rendering-driver opengl3 \
##     --script res://assets/custom/render_character_thumbs.gd

const SIZE := Vector2i(320, 360)
const HEROINE := "res://scenes/heroine/heroine_visual.tscn"
const HERO := "res://scenes/heroine/hero2_visual.tscn"
const PADDING := 1.12
## Three-quarter front view, a little from above.
const VIEW_DIR := Vector3(0.4, 0.3, 1.0)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	await _render("res://assets/custom/heroine/thumb.png", [[HEROINE, Vector3.ZERO, 0.0]])
	await _render("res://assets/custom/hero2/thumb.png", [[HERO, Vector3.ZERO, 0.0]])
	await _render("res://assets/custom/coop/thumb.png",
			[[HEROINE, Vector3(-0.42, 0.0, 0.0), 18.0], [HERO, Vector3(0.42, 0.0, 0.0), -18.0]])
	quit(0)

## models: [scene path, position, yaw degrees] each.
func _render(out_path: String, models: Array) -> void:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#fff4e6")
	env.ambient_light_energy = 0.75
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 0.95
	vp.add_child(sun)
	var holder := Node3D.new()
	vp.add_child(holder)
	for m: Array in models:
		var model := (load(m[0]) as PackedScene).instantiate() as Node3D
		holder.add_child(model)
		model.position = m[1]
		model.rotation_degrees.y = m[2]
		# Portrait without the tool in hand: the long net handle would dwarf the character.
		var tools := model.get_node_or_null(model.get("hand_tools_path")) as Node3D
		if tools != null:
			tools.visible = false
	for i in 6:
		await process_frame
	var box := _aabb(holder)
	var center := box.get_center()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var aspect := float(SIZE.x) / float(SIZE.y)
	cam.size = maxf(box.size.y, maxf(box.size.x, box.size.z) / aspect) * PADDING
	vp.add_child(cam)
	cam.position = center + VIEW_DIR.normalized() * 5.0
	cam.look_at(center, Vector3.UP)
	cam.current = true
	for i in 6:
		await process_frame
	var img := vp.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
	img.save_png(ProjectSettings.globalize_path(out_path))
	print("thumb ", out_path, " ", box)
	vp.queue_free()
	await process_frame

static func _aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).is_visible_in_tree():
			var m := n as MeshInstance3D
			var b := m.global_transform * m.get_aabb()
			result = b if first else result.merge(b)
			first = false
	return result
