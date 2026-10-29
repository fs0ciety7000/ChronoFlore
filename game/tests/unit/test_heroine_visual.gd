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
	for holder in ["Model/Heroine/Skeleton3D/HandR/HandTools", "Model/Heroine/Skeleton3D/Carry/CarryTools"]:
		for prop in v.get_node(holder).get_children():
			if (prop as Node3D).visible:
				visible_props += 1
	assert_eq(visible_props, 1, "only one prop shown (hand or shoulder)")
	belt.cycle(1)
	assert_eq(v.call("shown_tool_prop"), "Net", "cycling back shows the net")
	h.free()

func _hand(v: Node, prop: String) -> Node3D:
	return v.get_node("Model/Heroine/Skeleton3D/HandR/HandTools/" + prop) as Node3D

func test_net_rests_on_the_shoulder_between_swings() -> void:
	var v := VISUAL_SCENE.instantiate()
	tree.root.add_child(v)
	await tree.process_frame
	var carried: Node3D = v.call("carried_prop", &"Net")
	assert_true(carried != null, "a shoulder copy of the net")
	if carried == null:
		v.free()
		return
	assert_true(v.call("is_carrying"), "idle: carried")
	assert_true(carried.visible and not _hand(v, "Net").visible, "shoulder net shown, hand net hidden")
	assert_eq((carried.get_parent().get_parent() as BoneAttachment3D).bone_name, "chest", "rides the chest")
	# The carry transform is applied: in the visual's space the net matches carry_transform().
	var in_visual: Transform3D = (v as Node3D).global_transform.affine_inverse() * carried.global_transform
	var want: Transform3D = v.call("carry_transform")
	assert_true(in_visual.origin.distance_to(want.origin) < 0.06, "grip by the right hand")
	assert_true(in_visual.basis.y.normalized().dot(want.basis.y) > 0.97, "handle diagonal over the shoulder")
	var hoop := (v as Node3D).to_local((carried.get_node("Hoop") as Node3D).global_position)
	assert_true(hoop.y > 1.0 and hoop.z < -0.2 and hoop.x < 0.0, "hoop up behind the head, right side")
	v.call("set_walking", true)
	await tree.process_frame
	assert_true(v.call("is_carrying"), "walking: still carried")
	v.call("play_swing")
	assert_false(v.call("is_carrying"), "swing: off the shoulder")
	assert_true(_hand(v, "Net").visible and not carried.visible, "net in hand for the sweep")
	var ap: AnimationPlayer = v.call("animation_player")
	ap.advance(ap.get_animation("Swing").length + 0.05)
	await tree.process_frame
	assert_true(v.call("is_carrying") and carried.visible, "back on the shoulder after the swing")
	v.call("set_tool", load("res://data/tools/tranquilizer.tres") as ToolData)
	assert_false(v.call("is_carrying"), "dart gun is held, not carried")
	assert_true(_hand(v, "DartGun").visible, "dart gun in hand")
	v.call("set_tool", load("res://data/tools/harpoon.tres") as ToolData)
	assert_true(v.call("is_carrying") and (v.call("carried_prop", &"Harpoon") as Node3D).visible, "harpoon on the shoulder")
	v.call("play_shot")
	assert_true(_hand(v, "Harpoon").visible, "harpoon in hand for the shot")
	v.free()
