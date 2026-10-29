extends "res://tests/test_case.gd"

const VISUAL_SCENE := preload("res://scenes/heroine/heroine_visual.tscn")
const HEROINE_SCENE := preload("res://scenes/heroine/heroine.tscn")

func test_heroine_visual_animations() -> void:
	var v := VISUAL_SCENE.instantiate()
	tree.root.add_child(v)
	await tree.process_frame
	var ap: AnimationPlayer = v.call("animation_player")
	assert_true(ap != null, "has an AnimationPlayer")
	if ap == null:
		v.free()
		return
	for anim_name in ["Idle", "Walk", "Swing", "Hurt"]:
		assert_true(ap.has_animation(anim_name), "has " + anim_name)
	assert_eq(ap.get_animation("Idle").loop_mode, Animation.LOOP_LINEAR, "Idle loops")
	assert_eq(ap.get_animation("Walk").loop_mode, Animation.LOOP_LINEAR, "Walk loops")
	assert_eq(ap.get_animation("Swing").loop_mode, Animation.LOOP_NONE, "Swing is one-shot")
	assert_near(ap.get_animation("Swing").length, 0.45, 0.02, "Swing lasts ~0.45 s")
	assert_eq(ap.current_animation, "Idle", "starts idle")
	v.call("set_walking", true)
	assert_eq(ap.current_animation, "Walk", "walks when moving")
	v.call("play_swing")
	assert_eq(ap.current_animation, "Swing", "swings")
	v.call("set_walking", false)
	assert_eq(ap.current_animation, "Swing", "swing is not cut by locomotion")
	ap.advance(ap.get_animation("Swing").length + 0.05)
	assert_eq(ap.current_animation, "Idle", "back to idle after the swing")
	v.call("blink_hurt")
	assert_eq(ap.current_animation, "Hurt", "hurt flinch")
	var net := v.get_node_or_null("Model/Heroine/Skeleton3D/HandR")
	assert_true(net is BoneAttachment3D and (net as BoneAttachment3D).bone_name == "hand.R", "net on hand.R")
	v.free()

func test_heroine_swings_on_tool_used() -> void:
	var h := HEROINE_SCENE.instantiate() as Heroine
	tree.root.add_child(h)
	await tree.process_frame
	var ap: AnimationPlayer = h.get_node("Visual").call("animation_player")
	var belt := h.get_node("ToolBelt") as ToolBelt
	belt.tool_used.emit(null)
	assert_eq(ap.current_animation, "Swing", "tool_used plays Swing")
	h.free()

func test_hand_prop_follows_tool_changed() -> void:
	var h := HEROINE_SCENE.instantiate() as Heroine
	tree.root.add_child(h)
	await tree.process_frame
	var v := h.get_node("Visual")
	var belt := h.get_node("ToolBelt") as ToolBelt
	assert_eq(v.call("shown_tool_prop"), "Net", "net in hand before any tool")
	var net := load("res://data/tools/net.tres") as ToolData
	var dart := load("res://data/tools/tranquilizer.tres") as ToolData
	var harpoon := load("res://data/tools/harpoon.tres") as ToolData
	var tools: Array[ToolData] = [net, dart, harpoon]
	belt.set_tools(tools)
	assert_eq(v.call("shown_tool_prop"), "Net", "net tool shows the net")
	belt.select(1)
	assert_eq(v.call("shown_tool_prop"), "DartGun", "tranquilizer shows the dart gun")
	belt.select(2)
	assert_eq(v.call("shown_tool_prop"), "Harpoon", "harpoon shows the harpoon")
	var visible_props := 0
	for prop in v.get_node("Model/Heroine/Skeleton3D/HandR/HandTools").get_children():
		if (prop as Node3D).visible:
			visible_props += 1
	assert_eq(visible_props, 1, "only one prop in hand")
	belt.cycle(1)
	assert_eq(v.call("shown_tool_prop"), "Net", "cycling back shows the net")
	h.free()

func _hand(v: Node, prop: String) -> Node3D:
	return v.get_node("Model/Heroine/Skeleton3D/HandR/HandTools/" + prop) as Node3D

func _near_xf(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 0.01 and a.basis.y.normalized().dot(b.basis.y.normalized()) > 0.999

func _hand_world(v: Node) -> Vector3:
	var sk := v.get_node("Model/Heroine/Skeleton3D") as Skeleton3D
	return (v as Node3D).to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone("hand.R")).origin))

func test_net_rests_on_the_shoulder_between_swings() -> void:
	var v := VISUAL_SCENE.instantiate()
	tree.root.add_child(v)
	await tree.process_frame
	var net: Node3D = v.call("carried_prop", &"Net")
	assert_true(net != null and net == _hand(v, "Net"), "the net stays in hand.R")
	if net == null:
		v.free()
		return
	assert_true(v.call("is_carrying"), "idle: carried")
	assert_true(_near_xf(net.transform, v.call("carry_local", &"Net")), "carry transform applied when not swinging")
	# Gripped: the handle starts at the hand, which the Idle arm holds by the right collarbone.
	var hand := _hand_world(v)
	assert_true(hand.y > 0.42 and hand.x < -0.08, "right hand up by the shoulder (carry arm keyed)")
	var grip := (v as Node3D).to_local(net.global_position)
	assert_true(grip.distance_to(hand) < 0.08, "handle gripped in the hand")
	var hoop := (v as Node3D).to_local((net.get_node("Hoop") as Node3D).global_position)
	assert_true(hoop.y > 1.0 and hoop.z < -0.2 and hoop.x < 0.0, "hoop up behind the head, right side")
	v.call("set_walking", true)
	for i in 10:
		await tree.process_frame
	assert_true(v.call("is_carrying"), "walking: still carried")
	assert_true(_near_xf(net.transform, v.call("carry_local", &"Net")), "walking: carry transform")
	v.call("play_swing")
	assert_false(v.call("is_carrying"), "swing: off the shoulder")
	await tree.create_timer(0.12).timeout
	assert_true(_near_xf(net.transform, v.call("swing_local", &"Net")), "blended to the swing transform")
	var ap: AnimationPlayer = v.call("animation_player")
	ap.advance(ap.get_animation("Swing").length + 0.05)
	await tree.create_timer(0.12).timeout
	assert_true(v.call("is_carrying"), "back on the shoulder after the swing")
	assert_true(_near_xf(net.transform, v.call("carry_local", &"Net")), "blended back to the carry")
	v.call("set_tool", load("res://data/tools/tranquilizer.tres") as ToolData)
	assert_false(v.call("is_carrying"), "dart gun is held, not carried")
	assert_true(_hand(v, "DartGun").visible, "dart gun in hand")
	v.call("set_tool", load("res://data/tools/harpoon.tres") as ToolData)
	assert_true(v.call("is_carrying") and _hand(v, "Harpoon").visible, "harpoon on the shoulder")
	v.call("play_shot")
	assert_false(v.call("is_carrying"), "harpoon off the shoulder for the shot")
	v.free()

func test_net_prop_is_big_and_readable() -> void:
	var tools := (load("res://scenes/heroine/hand_tools.tscn") as PackedScene).instantiate()
	var hoop := (tools.get_node("Net/Hoop") as MeshInstance3D).mesh as TorusMesh
	var handle := (tools.get_node("Net/Handle") as MeshInstance3D).mesh as CylinderMesh
	var bag := (tools.get_node("Net/Bag") as MeshInstance3D).mesh as CylinderMesh
	assert_true((hoop.inner_radius + hoop.outer_radius) * 0.5 >= 0.38, "hoop radius ~0.4 m")
	assert_true(hoop.outer_radius - hoop.inner_radius >= 0.07, "thick rim")
	assert_true(handle.height >= 1.05, "handle ~1.1 m")
	assert_true(bag.height >= 0.45 and bag.top_radius >= 0.35, "big bag")
	assert_true(bag.material is ShaderMaterial, "mesh-pattern bag")
	tools.free()

func test_swing_trail_follows_the_hoop() -> void:
	var v := VISUAL_SCENE.instantiate()
	tree.root.add_child(v)
	await tree.process_frame
	assert_eq((v.call("trail_points") as Array).size(), 0, "no trail before a swing")
	v.call("play_swing")
	for i in 12:
		await tree.process_frame
	var pts: Array = v.call("trail_points")
	assert_true(pts.size() >= 3, "trail emitted during the swing")
	var hoop := v.get_node("Model/Heroine/Skeleton3D/HandR/HandTools/Net/Hoop") as Node3D
	if pts.size() > 0:
		assert_true((pts[-1] as Vector3).distance_to(hoop.global_position) < 0.3, "newest point at the hoop")
	var bag := v.get_node("Model/Heroine/Skeleton3D/HandR/HandTools/Net/Bag") as Node3D
	await tree.create_timer(0.75).timeout
	assert_eq((v.call("trail_points") as Array).size(), 0, "trail faded after the swing")
	assert_true(bag.scale.is_equal_approx(Vector3.ONE), "scoop settled")
	v.call("set_tool", load("res://data/tools/tranquilizer.tres") as ToolData)
	v.call("play_shot")
	for i in 5:
		await tree.process_frame
	assert_eq((v.call("trail_points") as Array).size(), 0, "no net trail for a shot")
	v.free()

## Exported builds re-pack scenes (instantiate + PackedScene.pack): nodes saved inside the
## instanced .glb were dropped there, so no tool was ever shown in hand outside the editor.
func test_hand_tools_survive_a_scene_repack() -> void:
	for path in ["res://scenes/heroine/heroine_visual.tscn", "res://scenes/heroine/hero2_visual.tscn"]:
		var edit := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		var repacked := PackedScene.new()
		assert_eq(repacked.pack(edit), OK, path + " re-packs")
		edit.free()
		var v := repacked.instantiate() as Node3D
		tree.root.add_child(v)
		await tree.process_frame
		var tools := v.get_node_or_null(v.get("hand_tools_path")) as Node3D
		assert_true(tools != null, path + ": hand tools built after a re-pack")
		if tools != null:
			var attach := tools.get_parent() as BoneAttachment3D
			assert_true(attach != null and attach.bone_name == "hand.R", path + ": tools on hand.R")
			var net := tools.get_node_or_null(^"Net") as Node3D
			assert_true(net != null and net.is_visible_in_tree(), path + ": net shown in hand")
			assert_eq(v.call("shown_tool_prop"), "Net", path + ": net is the shown prop")
		v.free()
