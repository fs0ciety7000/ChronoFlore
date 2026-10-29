extends "res://tests/test_case.gd"
## Task C3: pure co-op rules (population, nightmares, camera framing, leash, nearest player).

func test_constants() -> void:
	assert_near(CoopRules.POPULATION_FACTOR, 1.3, 1e-6, "population x1.3")
	assert_eq(CoopRules.EXTRA_NIGHTMARES, 1, "one more nightmare")
	assert_near(CoopRules.LEASH_DISTANCE, 14.0, 1e-6, "leash 14 m")
	assert_near(CoopRules.CAMERA_MAX_SCALE, 1.5, 1e-6, "camera up to x1.5")

func test_population() -> void:
	assert_eq(CoopRules.population(6, true), 8, "6 -> 8 in co-op (7.8 rounded)")
	assert_eq(CoopRules.population(7, true), 9, "7 -> 9 (9.1 rounded)")
	assert_eq(CoopRules.population(8, true), 10, "8 -> 10 (10.4 rounded)")
	assert_eq(CoopRules.population(5, true), 7, "5 -> 7 (6.5 rounded half away)")
	assert_eq(CoopRules.population(0, true), 0, "nothing stays nothing")
	assert_eq(CoopRules.population(6, false), 6, "solo unchanged")

func test_nightmares() -> void:
	assert_eq(CoopRules.nightmares(1, true), 2, "+1 in co-op")
	assert_eq(CoopRules.nightmares(3, true), 4, "+1 at 3")
	assert_eq(CoopRules.nightmares(1, false), 1, "solo unchanged")

func test_camera_size() -> void:
	assert_near(CoopRules.camera_size(12, 0), 12.0, 1e-6, "together: solo size")
	assert_near(CoopRules.camera_size(12, 14), 18.0, 1e-6, "at the leash: x1.5")
	assert_near(CoopRules.camera_size(12, 7), 15.0, 1e-6, "linear in between")
	assert_near(CoopRules.camera_size(12, 30), 18.0, 1e-6, "never beyond x1.5")
	assert_near(CoopRules.camera_size(10, -3), 10.0, 1e-6, "never under the solo size")

func test_leash() -> void:
	var other := Vector2(1, 2)
	assert_eq(CoopRules.leash(Vector2(5, 2), other), Vector2(5, 2), "within reach: unchanged")
	var far := CoopRules.leash(Vector2(31, 2), other)
	assert_near(far.distance_to(other), 14.0, 1e-4, "held at 14 m")
	assert_near(far.y, 2.0, 1e-4, "on the same line")
	assert_true(far.x > other.x, "same side")
	var diag := CoopRules.leash(Vector2(21, 22), other)
	assert_near(diag.distance_to(other), 14.0, 1e-4, "diagonal held at 14 m")
	assert_near((diag - other).angle(), (Vector2(21, 22) - other).angle(), 1e-4, "keeps the direction")
	assert_eq(CoopRules.leash(other, other), other, "same point stays")

func test_nearest() -> void:
	var players := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	assert_eq(CoopRules.nearest(Vector2(2, 1), players), 0, "P1 nearer")
	assert_eq(CoopRules.nearest(Vector2(8, -3), players), 1, "P2 nearer")
	assert_eq(CoopRules.nearest(Vector2(5, 0), players), 0, "tie -> first")
	assert_eq(CoopRules.nearest(Vector2(5, 0), PackedVector2Array([Vector2(3, 3)])), 0, "solo -> 0")
	assert_eq(CoopRules.nearest(Vector2(5, 0), PackedVector2Array()), -1, "nobody -> -1")
