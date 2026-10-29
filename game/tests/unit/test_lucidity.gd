extends "res://tests/test_case.gd"

func test_starts_full() -> void:
	var l := Lucidity.new()
	assert_eq(l.petals, 5, "petals")
	assert_false(l.is_empty(), "not empty")

func test_lose_and_deplete() -> void:
	var l := Lucidity.new()
	var depleted: Array[int] = [0]
	l.depleted.connect(func() -> void: depleted[0] += 1)
	for i in 5:
		l.lose_petal()
	assert_eq(l.petals, 0, "zero")
	assert_eq(depleted[0], 1, "depleted once")
	l.lose_petal()
	assert_eq(l.petals, 0, "stays zero")
	assert_eq(depleted[0], 1, "depleted still once")
	assert_true(l.is_empty(), "empty")

func test_regrow_after_three_captures() -> void:
	var l := Lucidity.new()
	l.lose_petal()
	for i in 3:
		l.register_capture()
	assert_eq(l.petals, 5, "regrown")
	assert_eq(l.streak, 0, "streak reset")

func test_loss_resets_streak() -> void:
	var l := Lucidity.new()
	l.lose_petal()
	l.register_capture()
	l.register_capture()
	l.lose_petal()
	l.register_capture()
	l.register_capture()
	assert_eq(l.petals, 3, "no regrow")

func test_no_regrow_above_max() -> void:
	var l := Lucidity.new()
	for i in 3:
		l.register_capture()
	assert_eq(l.petals, 5, "still max")

func test_hit_invulnerability() -> void:
	var l := Lucidity.new()
	assert_true(l.take_hit(10.0), "first hit")
	assert_false(l.take_hit(10.0), "same frame")
	assert_false(l.take_hit(11.4), "within 1.5 s")
	assert_true(l.take_hit(11.6), "after 1.5 s")
	assert_eq(l.petals, 3, "two petals lost")

func test_escape_ignores_invulnerability() -> void:
	var l := Lucidity.new()
	l.take_hit(0.0)
	l.lose_petal()
	assert_eq(l.petals, 3, "hit + escape")
