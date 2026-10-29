extends "res://tests/test_case.gd"

const HERO2_SCENE := preload("res://scenes/heroine/hero2_visual.tscn")
const HEROINE_VISUAL_SCENE := preload("res://scenes/heroine/heroine_visual.tscn")

func test_hero2_visual_instantiates() -> void:
	var v := HERO2_SCENE.instantiate()
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
	# Same interface as the heroine visual, so the two are interchangeable.
	var heroine_visual := HEROINE_VISUAL_SCENE.instantiate()
	for m in heroine_visual.get_script().get_script_method_list():
		var method_name: String = m["name"]
		if not method_name.begins_with("_"):
			assert_true(v.has_method(method_name), "hero2 visual has " + method_name)
	heroine_visual.free()
	v.call("set_walking", true)
	assert_eq(ap.current_animation, "Walk", "walks when moving")
	v.call("play_swing")
	assert_eq(ap.current_animation, "Swing", "swings")
	v.call("blink_hurt")
	assert_eq(ap.current_animation, "Hurt", "hurt flinch")
	var hand := v.get_node_or_null("Model/Hero2/Skeleton3D/HandR")
	assert_true(hand is BoneAttachment3D and (hand as BoneAttachment3D).bone_name == "hand.R", "props on hand.R")
	assert_eq(v.call("shown_tool_prop"), "Net", "net in hand by default")
	v.call("set_tool", load("res://data/tools/harpoon.tres") as ToolData)
	assert_eq(v.call("shown_tool_prop"), "Harpoon", "tool prop follows set_tool")
	v.free()
