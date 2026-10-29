extends "res://tests/test_case.gd"

const HEROINE_SCENE := preload("res://scenes/heroine/heroine.tscn")

func test_best_target_in_cone() -> void:
	var targets := PackedVector2Array([Vector2(5, 1), Vector2(5, -4), Vector2(-5, 0)])
	assert_eq(AimAssist.best_target(Vector2.ZERO, Vector2(1, 0), targets, 10.0), 0, "smallest angle in cone")

func test_none_outside_cone() -> void:
	assert_eq(AimAssist.best_target(Vector2.ZERO, Vector2(1, 0), PackedVector2Array([Vector2(0, 5)]), 10.0), -1, "outside cone")
	assert_eq(AimAssist.best_target(Vector2.ZERO, Vector2(1, 0), PackedVector2Array([Vector2(20, 0)]), 10.0), -1, "out of range")
	assert_eq(AimAssist.best_target(Vector2.ZERO, Vector2(1, 0), PackedVector2Array(), 10.0), -1, "no targets")

func test_ties_prefer_distance() -> void:
	var targets := PackedVector2Array([Vector2(8, 0), Vector2(3, 0)])
	assert_eq(AimAssist.best_target(Vector2.ZERO, Vector2(1, 0), targets, 10.0), 1, "closer wins on equal angle")

func test_assisted_strength() -> void:
	var target := PackedVector2Array([Vector2(5, 5 * tan(deg_to_rad(20.0)))])
	var m := AimAssist.assisted_direction(Vector2.ZERO, Vector2(1, 0), target, 10.0, AimAssist.Source.MOUSE)
	assert_near(rad_to_deg(m.angle()), 6.0, 0.01, "mouse turns 30% of 20 deg")
	var a := AimAssist.assisted_direction(Vector2.ZERO, Vector2(1, 0), target, 10.0, AimAssist.Source.AUTO)
	assert_near(rad_to_deg(a.angle()), 20.0, 0.01, "auto aims at target")
	assert_near(a.length(), 1.0, 0.0001, "unit length")
	var none := AimAssist.assisted_direction(Vector2.ZERO, Vector2(1, 0), PackedVector2Array(), 10.0, AimAssist.Source.AUTO)
	assert_eq(none, Vector2(1, 0), "unchanged without target")

func test_pick_source() -> void:
	var S := AimAssist.Source
	assert_eq(AimAssist.pick_source(S.MOUSE, false, Vector2(0, 0.8), Vector2.ZERO, true), S.STICK, "stick wins")
	assert_eq(AimAssist.pick_source(S.STICK, true, Vector2.ZERO, Vector2.ZERO, true), S.MOUSE, "mouse moved")
	assert_eq(AimAssist.pick_source(S.STICK, false, Vector2.ZERO, Vector2(1, 0), true), S.MOVE, "idle stick -> move")
	assert_eq(AimAssist.pick_source(S.MOVE, false, Vector2.ZERO, Vector2(1, 0), false), S.MOVE, "unplugged pad keeps move")
	assert_eq(AimAssist.pick_source(S.STICK, false, Vector2.ZERO, Vector2(1, 0), false), S.MOVE, "unplug while on stick -> move")
	assert_eq(AimAssist.pick_source(S.MOUSE, false, Vector2.ZERO, Vector2(1, 0), true), S.MOVE, "pad player on left stick -> move")
	assert_eq(AimAssist.pick_source(S.MOUSE, false, Vector2.ZERO, Vector2(1, 0), false), S.MOUSE, "keyboard+mouse stays on mouse")
	assert_eq(AimAssist.pick_source(S.MOUSE, false, Vector2.ZERO, Vector2.ZERO, true), S.MOUSE, "mouse stays when pad idle")

func test_input_actions_exist() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down", "aim_left", "aim_right",
			"aim_up", "aim_down", "use_tool", "next_tool", "prev_tool", "tool_1", "tool_2",
			"tool_3", "pause"]:
		assert_true(InputMap.has_action(action), "has " + action)
		if InputMap.has_action(action):
			assert_true(InputMap.action_get_events(action).size() >= 1, action + " has events")

# The runner starts before the root is inside the tree: wait a frame so _ready and globals work.
func _heroine() -> Heroine:
	var h := HEROINE_SCENE.instantiate() as Heroine
	tree.root.add_child(h)
	await tree.process_frame
	return h

func test_heroine_default_aim() -> void:
	var h: Heroine = await _heroine()
	assert_eq(h.aim_dir, Vector2(0, 1), "default aim faces +Z")
	assert_true(h.is_in_group("heroine"), "in heroine group")
	assert_true(h.get_node_or_null("Visual/Model") != null, "visual built")
	assert_eq(h.facing(), Vector2(0, 1), "facing")
	assert_eq(h.collision_layer, 2, "layer 2")
	assert_eq(h.collision_mask, 1, "mask 1")
	h.free()

func test_screen_to_world() -> void:
	var up := Heroine.screen_to_world(Vector2(0, -1))
	assert_near(up.x, -0.7071, 0.001, "up x")
	assert_near(up.y, -0.7071, 0.001, "up z")
	var right := Heroine.screen_to_world(Vector2(1, 0))
	assert_near(right.x, 0.7071, 0.001, "right x")
	assert_near(right.y, -0.7071, 0.001, "right z")

func test_update_aim_sources() -> void:
	var h: Heroine = await _heroine()
	h.global_position = Vector3(2, 0, 2)
	h.update_aim(true, Vector3(2, 0, 6), Vector2.ZERO, Vector2.ZERO, false)
	assert_eq(h.aim_source, AimAssist.Source.MOUSE, "mouse source")
	assert_near(h.aim_dir.y, 1.0, 0.001, "aims at mouse point")
	h.update_aim(false, null, Vector2(1, 0), Vector2.ZERO, true)
	assert_eq(h.aim_source, AimAssist.Source.STICK, "stick source")
	assert_near(h.aim_dir.x, 0.7071, 0.001, "stick right")
	var before := h.aim_dir
	h.update_aim(true, null, Vector2.ZERO, Vector2.ZERO, false)
	assert_eq(h.aim_dir, before, "no camera point keeps aim")
	h.update_aim(false, null, Vector2(1, 0), Vector2.ZERO, true)
	h.update_aim(false, null, Vector2.ZERO, Vector2(0, -1), true)
	assert_eq(h.aim_source, AimAssist.Source.MOVE, "move source")
	assert_near(h.aim_dir.x, -0.7071, 0.001, "move up")
	h.update_aim(false, null, Vector2.ZERO, Vector2.ZERO, false)
	assert_true(h.aim_dir.length() > 0.99, "aim never zero")
	h.free()

func test_nightmare_knockback() -> void:
	var h: Heroine = await _heroine()
	h.lucidity = Lucidity.new(5)
	var shape := IslandShape.new()
	shape.outline = PackedVector2Array([Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10), Vector2(-10, 10)])
	h.island = shape
	h.global_position = Vector3.ZERO
	assert_true(h.take_nightmare_hit(Vector2(-0.5, 0.0)), "accepted hit")
	assert_true(h.is_knocked_back(), "knockback started")
	assert_false(h.take_nightmare_hit(Vector2(-0.5, 0.0)), "second hit refused while invulnerable")
	for i in 20:
		h._physics_process(1.0 / 60.0)
	assert_false(h.is_knocked_back(), "knockback over")
	assert_near(h.global_position.x, Heroine.KNOCKBACK_DISTANCE, 0.05, "pushed 1.5 m away from the Ronce")
	assert_near(h.global_position.z, 0.0, 0.05, "along the hit direction")
	# Near the edge the knockback target is clamped inside the island.
	h.lucidity = Lucidity.new(5)
	h.global_position = Vector3(9.0, 0.0, 0.0)
	h.take_nightmare_hit(Vector2(8.5, 0.0))
	for i in 20:
		h._physics_process(1.0 / 60.0)
	assert_true(h.global_position.x <= 10.0 - Heroine.EDGE_MARGIN + 0.05, "clamped inside the island")
	h.free()

func test_nightmare_hit() -> void:
	var h: Heroine = await _heroine()
	h.take_nightmare_hit() # no lucidity: no-op
	h.lucidity = Lucidity.new(5)
	var hits := [0]
	h.nightmare_hit.connect(func() -> void: hits[0] += 1)
	h.take_nightmare_hit()
	h.take_nightmare_hit()
	assert_eq(hits[0], 1, "second hit invulnerable")
	assert_eq(h.lucidity.petals, 4, "one petal lost")
	h.free()
