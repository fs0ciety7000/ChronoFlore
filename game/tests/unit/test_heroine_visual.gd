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
