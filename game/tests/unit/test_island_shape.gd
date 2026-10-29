extends "res://tests/test_case.gd"

func _square() -> IslandShape:
	var s := IslandShape.new()
	s.outline = PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	return s

func test_contains() -> void:
	var s := _square()
	assert_true(s.contains(Vector2(5, 5)), "inside")
	assert_false(s.contains(Vector2(11, 5)), "outside")

func test_distance_and_normal() -> void:
	var s := _square()
	assert_near(s.distance_to_edge(Vector2(5, 1)), 1.0, 0.0001, "distance inside")
	assert_near(s.distance_to_edge(Vector2(12, 5)), 2.0, 0.0001, "distance outside")
	var n := s.outward_normal(Vector2(5, 1))
	assert_near(n.x, 0.0, 0.0001, "normal x")
	assert_near(n.y, -1.0, 0.0001, "normal y")
	var n2 := s.outward_normal(Vector2(12, 5))
	assert_near(n2.x, 1.0, 0.0001, "normal outside x")

func test_clamp_inside() -> void:
	var s := _square()
	var c := s.clamp_inside(Vector2(12, 5), 0.5)
	assert_near(c.x, 9.5, 0.0001, "clamp x")
	assert_near(c.y, 5.0, 0.0001, "clamp y")
	var same := s.clamp_inside(Vector2(5, 5), 0.5)
	assert_eq(same, Vector2(5, 5), "unchanged inside")
	var near_edge := s.clamp_inside(Vector2(5, 0.2), 0.5)
	assert_near(near_edge.y, 0.5, 0.0001, "pushed in from edge")

func test_random_point() -> void:
	var s := _square()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 50:
		var p := s.random_point(rng, 1.0)
		assert_true(s.contains(p) and s.distance_to_edge(p) >= 1.0 - 0.0001, "point %s" % p)

func test_obstacles() -> void:
	var s := _square()
	s.obstacles = PackedVector3Array([Vector3(5, 5, 2)])
	assert_false(s.is_clear(Vector2(6, 5)), "inside the obstacle")
	assert_false(s.is_clear(Vector2(7.5, 5), 1.0), "within the margin")
	assert_true(s.is_clear(Vector2(8.5, 5), 1.0), "clear beyond the margin")
	var out := s.push_out_of_obstacles(Vector2(6, 5), 0.5)
	assert_near(out.x, 7.5, 0.0001, "pushed out radially")
	assert_eq(s.push_out_of_obstacles(Vector2(1, 1), 0.5), Vector2(1, 1), "clear point unchanged")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 50:
		var p := s.random_point(rng, 0.5)
		assert_true(s.is_clear(p, 0.5), "random point avoids the obstacle %s" % p)

func test_clamp_walkable_stays_clear_near_the_edge() -> void:
	var s := _square()
	s.obstacles = PackedVector3Array([Vector3(9.5, 5, 1.5)]) # pond touching the east edge
	var p := s.clamp_walkable(Vector2(11, 5), 0.5, 0.4)
	assert_true(s.is_clear(p, 0.4 - 0.0001), "out of the obstacle after clamping (%s)" % p)
	var q := s.clamp_walkable(Vector2(3, 3), 0.5, 0.4)
	assert_eq(q, Vector2(3, 3), "free point unchanged")

func test_centroid() -> void:
	var c := _square().centroid()
	assert_near(c.x, 5.0, 0.0001, "cx")
	assert_near(c.y, 5.0, 0.0001, "cy")
