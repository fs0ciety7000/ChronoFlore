extends "res://tests/test_case.gd"

func test_starts_at_zero() -> void:
	var c := NightClock.new()
	assert_near(c.progress(), 0.0, 0.0001, "progress")
	assert_false(c.is_dawn(), "not dawn")

func test_add_minutes() -> void:
	var c := NightClock.new()
	c.add_minutes(20)
	assert_eq(c.minutes, 20, "minutes")
	assert_near(c.hour(), 0.3333, 0.001, "hour")

func test_clamps_and_dawn_once() -> void:
	var c := NightClock.new()
	var dawns: Array[int] = [0]
	c.dawn_reached.connect(func() -> void: dawns[0] += 1)
	c.add_minutes(460)
	c.add_minutes(60)
	assert_eq(c.minutes, 480, "clamped")
	assert_true(c.is_dawn(), "dawn")
	c.add_minutes(20)
	assert_eq(c.minutes, 480, "still 480")
	assert_eq(dawns[0], 1, "dawn emitted once")

func test_progress_half() -> void:
	var c := NightClock.new()
	c.add_minutes(240)
	assert_near(c.progress(), 0.5, 0.0001, "half")

func test_minutes_changed() -> void:
	var c := NightClock.new()
	var seen: Array[int] = []
	c.minutes_changed.connect(func(m: int) -> void: seen.append(m))
	c.add_minutes(20)
	assert_eq(seen, [20] as Array[int], "emitted 20")
	c.add_minutes(460)
	var n: int = seen.size()
	c.add_minutes(20)
	assert_eq(seen.size(), n, "no emit at dawn")
