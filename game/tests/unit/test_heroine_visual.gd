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
