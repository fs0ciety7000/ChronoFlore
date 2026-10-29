# Run with: godot --headless --path game --script res://tests/test_runner.gd
extends SceneTree

var passed := 0
var failed := 0

func _initialize() -> void:
	test_sanity()
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		passed += 1
	else:
		failed += 1
		push_error("FAIL %s: expected %s, got %s" % [label, expected, actual])

func test_sanity() -> void:
	assert_eq(ProjectSettings.get_setting("application/config/name"), "ChronoFlore", "project_name")
