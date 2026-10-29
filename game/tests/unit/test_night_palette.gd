extends "res://tests/test_case.gd"

func _close(a: Color, b: Color, label: String) -> void:
	assert_near(a.r, b.r, 0.004, label + " r")
	assert_near(a.g, b.g, 0.004, label + " g")
	assert_near(a.b, b.b, 0.004, label + " b")

func test_keyframes() -> void:
	_close(NightPalette.sample(0.0)["background"], Color("f6efe0"), "bg 0")
	_close(NightPalette.sample(1.0)["background"], Color("f7c9d4"), "bg 1")
	_close(NightPalette.sample(0.375)["sun_color"], Color("8d8fd8"), "sun 0.375")
	assert_near(NightPalette.sample(0.5)["plant_glow"], 1.0, 0.0001, "glow mid")
	assert_near(NightPalette.sample(0.0)["sun_pitch_deg"], -55.0, 0.0001, "pitch 0")
	assert_near(NightPalette.sample(1.0)["sun_energy"], 0.8, 0.0001, "energy 1")

func test_interpolation() -> void:
	# Halfway between 0.0 and 0.25 keyframes.
	assert_near(NightPalette.sample(0.125)["sun_energy"], 0.975, 0.0001, "energy mid")
	assert_near(NightPalette.sample(0.3125)["plant_glow"], 0.5, 0.0001, "glow mid-ramp")

func test_clamped() -> void:
	assert_eq(NightPalette.sample(-1.0), NightPalette.sample(0.0), "below 0")
	assert_eq(NightPalette.sample(2.0), NightPalette.sample(1.0), "above 1")
