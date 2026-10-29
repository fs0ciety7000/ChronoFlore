extends "res://tests/test_case.gd"
## Body facing rules: walking -> faces the walk, idle -> faces the aim, tool use -> faces the
## (assisted) shot for the swing, then the walk again. The aim chevron always shows aim_dir.

const HEROINE_SCENE := preload("res://scenes/heroine/heroine.tscn")

func _heroine() -> Heroine:
	var h := HEROINE_SCENE.instantiate() as Heroine
	tree.root.add_child(h)
	await tree.process_frame
	h.set_physics_process(false) # the tests drive facing themselves
	return h

func _yaw(h: Heroine) -> float:
	return (h.get_node("Visual") as Node3D).rotation.y

func _assert_yaw(h: Heroine, dir: Vector2, label: String) -> void:
	assert_near(angle_difference(_yaw(h), atan2(dir.x, dir.y)), 0.0, 0.02, label)

func _settle(h: Heroine, seconds: float = 0.5) -> void:
	var steps := int(seconds * 60.0)
	for i in steps:
		h.tick_facing(1.0 / 60.0)

func test_moving_faces_the_walk_not_the_mouse() -> void:
	var h: Heroine = await _heroine()
	h.update_aim(true, Vector3(5, 0, 0), Vector2.ZERO, Vector2.ZERO, false) # mouse to +X
	assert_eq(h.aim_source, AimAssist.Source.MOUSE, "mouse aim")
	var walk := Heroine.screen_to_world(Vector2(-1, 0)) # screen left: away from the mouse
	h.set_move_intent(walk)
	_settle(h)
	assert_true(h.body_facing().is_equal_approx(walk.normalized()), "body faces the walk")
	_assert_yaw(h, walk, "visual turned to the walk")
	assert_near(h.aim_dir.x, 1.0, 1e-4, "aim stays on the mouse")
	h.free()

func test_every_screen_direction_is_faced() -> void:
	var h: Heroine = await _heroine()
	for v in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
			Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var walk := Heroine.screen_to_world(v.normalized())
		h.set_move_intent(walk)
		_settle(h)
		_assert_yaw(h, walk, "faces screen %s" % str(v))
	h.free()

func test_turn_is_quick_but_not_a_pop() -> void:
	var h: Heroine = await _heroine()
	h.set_move_intent(Vector2(0, -1)) # half a turn from the default +Z
	h.tick_facing(1.0 / 60.0)
	var after_one := absf(angle_difference(_yaw(h), PI))
	assert_true(after_one > 0.1, "not snapped in one frame")
	_settle(h, 0.3)
	_assert_yaw(h, Vector2(0, -1), "turned within 0.3 s")
	h.free()

func test_idle_faces_the_aim() -> void:
	var h: Heroine = await _heroine()
	h.set_move_intent(Vector2(1, 0))
	_settle(h)
	h.set_move_intent(Vector2.ZERO)
	h.update_aim(true, Vector3(0, 0, -4), Vector2.ZERO, Vector2.ZERO, false)
	_settle(h)
	assert_true(h.body_facing().is_equal_approx(Vector2(0, -1)), "idle: body follows the aim")
	_assert_yaw(h, Vector2(0, -1), "visual faces the mouse")
	h.free()

func test_tool_use_faces_the_shot_for_the_swing_then_the_walk() -> void:
	var h: Heroine = await _heroine()
	var belt := h.get_node("ToolBelt") as ToolBelt
	belt.set_tools([load("res://data/tools/net.tres")] as Array[ToolData])
	var walk := Vector2(-1, 0)
	h.set_move_intent(walk)
	_settle(h)
	h.update_aim(true, Vector3(0, 0, 3), Vector2.ZERO, Vector2.ZERO, false)
	assert_true(belt.try_use(Vector3.UP * 0.5, h.aim_dir), "net used")
	assert_true(h.is_facing_tool(), "tool facing on")
	_assert_yaw(h, Vector2(0, 1), "turned to the aim at once for the swing")
	_settle(h, Heroine.TOOL_FACE_TIME - 0.05)
	_assert_yaw(h, Vector2(0, 1), "keeps facing the swing while walking")
	_settle(h, 0.1 + 0.5)
	assert_false(h.is_facing_tool(), "swing over")
	_assert_yaw(h, walk, "back to facing the walk")
	h.free()

func test_shot_faces_the_assisted_direction() -> void:
	var h: Heroine = await _heroine()
	var belt := h.get_node("ToolBelt") as ToolBelt
	belt.last_use_dir = Vector2(0.6, 0.8)
	belt.tool_used.emit(load("res://data/tools/tranquilizer.tres") as ToolData)
	assert_true(h.body_facing().is_equal_approx(Vector2(0.6, 0.8)), "faces the assisted shot")
	var v := h.get_node("Visual")
	assert_eq(v.call("shot_count"), 1, "a shot plays the recoil")
	var ap: AnimationPlayer = v.call("animation_player")
	assert_true(ap.current_animation != "Swing", "a shot is not the net swing")
	h.free()

func test_aim_marker_sits_in_front_toward_the_aim() -> void:
	var h: Heroine = await _heroine()
	var marker := h.aim_marker()
	assert_true(marker != null and marker.get_parent() == h, "chevron on the body")
	h.update_aim(true, Vector3(-3, 0, 0), Vector2.ZERO, Vector2.ZERO, false)
	h.set_move_intent(Vector2(0, 1)) # walking elsewhere: the chevron still shows the aim
	h.tick_facing(1.0 / 60.0)
	assert_near(marker.position.x, -Heroine.AIM_MARKER_DISTANCE, 1e-3, "1.2 m toward the aim")
	assert_near(marker.position.z, 0.0, 1e-3, "on the aim line")
	assert_true(marker.position.y > 0.0 and marker.position.y < 0.1, "on the ground")
	assert_near(marker.rotation.y, atan2(-1.0, 0.0), 1e-3, "points along the aim")
	h.free()
