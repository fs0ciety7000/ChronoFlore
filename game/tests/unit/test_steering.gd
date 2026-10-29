extends "res://tests/test_case.gd"

func _square() -> IslandShape:
	var s := IslandShape.new()
	s.outline = PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(20, 20), Vector2(0, 20)])
	return s

func test_flee_center() -> void:
	var d := Steering.flee(Vector2(5, 5), Vector2(4, 5), _square(), false)
	assert_true(d.x > 0.9, "flees away from threat (x = %s)" % d.x)
	assert_near(d.length(), 1.0, 0.0001, "unit length")

func test_flee_near_edge_stays_in() -> void:
	var island := _square()
	var p := Vector2(0.5, 10)
	var d := Steering.flee(p, Vector2(3, 10), island, false)
	assert_true(d.dot(island.outward_normal(p)) <= 0.0, "never heads out when calm (dot = %s)" % d.dot(island.outward_normal(p)))
	assert_near(d.length(), 1.0, 0.0001, "unit length")

func test_flee_near_edge_oblique_stays_in() -> void:
	var island := _square()
	var p := Vector2(1.5, 10)
	var d := Steering.flee(p, Vector2(4, 12), island, false)
	assert_true(d.dot(island.outward_normal(p)) <= 0.0, "oblique flee bent inward")

func test_flee_panic_goes_out() -> void:
	var island := _square()
	var p := Vector2(0.5, 10)
	var d := Steering.flee(p, Vector2(3, 10), island, true)
	assert_true(d.dot(island.outward_normal(p)) > 0.5, "panic heads to the edge")

func test_zigzag_angle() -> void:
	var dir := Vector2(1, 0)
	var a := Steering.zigzag(dir, 1)
	var b := Steering.zigzag(dir, -1)
	assert_near(absf(rad_to_deg(dir.angle_to(a))), 35.0, 0.01, "+ phase 35 deg")
	assert_near(absf(rad_to_deg(dir.angle_to(b))), 35.0, 0.01, "- phase 35 deg")
	assert_true(signf(dir.angle_to(a)) != signf(dir.angle_to(b)), "phases on opposite sides")

func test_seek() -> void:
	var d := Steering.seek(Vector2(1, 1), Vector2(1, 4))
	assert_near(d.x, 0.0, 0.0001, "seek x")
	assert_near(d.y, 1.0, 0.0001, "seek y")
	assert_eq(Steering.seek(Vector2(2, 2), Vector2(2, 2)), Vector2.ZERO, "seek on target is zero")

func test_in_cone() -> void:
	assert_true(Steering.in_cone(Vector2.ZERO, Vector2(1, 0), Vector2(5, 0), 45.0, 30.0), "ahead at 5 m")
	assert_false(Steering.in_cone(Vector2.ZERO, Vector2(1, 0), Vector2(-5, 0), 45.0, 30.0), "behind")
	assert_false(Steering.in_cone(Vector2.ZERO, Vector2(1, 0), Vector2(5, 6), 45.0, 30.0), "outside angle")
	assert_false(Steering.in_cone(Vector2.ZERO, Vector2(1, 0), Vector2(31, 0), 45.0, 30.0), "out of range")
