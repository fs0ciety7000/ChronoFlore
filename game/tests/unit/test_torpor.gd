extends "res://tests/test_case.gd"

func test_darts_slow() -> void:
	var t := Torpor.new()
	t.add_dart()
	assert_near(t.speed_factor(), 0.75, 0.0001, "1 dart")
	t.add_dart()
	assert_near(t.speed_factor(), 0.5, 0.0001, "2 darts")

func test_three_darts_sleep() -> void:
	var t := Torpor.new()
	var slept: Array[int] = [0]
	t.fell_asleep.connect(func() -> void: slept[0] += 1)
	for i in 3:
		t.add_dart()
	assert_true(t.is_asleep(), "asleep")
	assert_near(t.speed_factor(), 0.0, 0.0001, "speed 0")
	assert_eq(slept[0], 1, "fell_asleep emitted")
	t.add_dart()
	assert_eq(t.charges, 0, "no charges while asleep")
	t.tick(3.1)
	assert_false(t.is_asleep(), "awake")
	assert_eq(t.charges, 0, "charges 0")
	assert_near(t.speed_factor(), 1.0, 0.0001, "speed 1")

func test_decay() -> void:
	var t := Torpor.new()
	t.add_dart()
	t.add_dart()
	t.tick(2.6)
	assert_eq(t.charges, 1, "one charge left")
	t.tick(2.6)
	assert_eq(t.charges, 0, "none left")

func test_dart_restarts_decay() -> void:
	var t := Torpor.new()
	t.add_dart()
	t.tick(2.0)
	t.add_dart()
	t.tick(2.0)
	assert_eq(t.charges, 2, "still 2")

func test_pin() -> void:
	var t := Torpor.new()
	t.pin()
	assert_true(t.is_pinned(), "pinned")
	assert_near(t.speed_factor(), 0.0, 0.0001, "speed 0")
	t.tick(3.1)
	assert_false(t.is_pinned(), "free")

func test_net_rules() -> void:
	var t := Torpor.new()
	assert_false(t.net_can_capture(false), "0 charges")
	t.add_dart()
	assert_false(t.net_can_capture(false), "1 charge")
	t.add_dart()
	assert_true(t.net_can_capture(false), "2 charges")
	t.add_dart()
	assert_true(t.net_can_capture(false), "asleep")
	var p := Torpor.new()
	p.pin()
	assert_true(p.net_can_capture(false), "pinned")
	assert_true(Torpor.new().net_can_capture(true), "emerging")
