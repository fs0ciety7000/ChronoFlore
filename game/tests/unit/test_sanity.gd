extends "res://tests/test_case.gd"

func test_project_name() -> void:
	assert_eq(ProjectSettings.get_setting("application/config/name"), "ChronoFlore", "project_name")
