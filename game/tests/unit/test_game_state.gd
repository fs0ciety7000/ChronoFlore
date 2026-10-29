extends "res://tests/test_case.gd"

const PATH := "user://test_gs.json"

var _saved_path: String
var _saved_herbarium: Herbarium

func _begin() -> void:
	_saved_path = GameState.save_path
	_saved_herbarium = GameState.herbarium
	GameState.save_path = PATH
	GameState.herbarium = Herbarium.new()
	GameState.begin_night()
	_remove_file()

func _end() -> void:
	_remove_file()
	GameState.save_path = _saved_path
	GameState.herbarium = _saved_herbarium

func _remove_file() -> void:
	for p in [PATH, PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func _species(id: StringName) -> PlantSpecies:
	return GameState.catalog.species_by_id(id)

func test_game_state_record_saves_on_discovery() -> void:
	_begin()
	var result := GameState.record(_species(&"revette"))
	assert_true(bool(result["new_species"]), "first capture is a discovery")
	assert_true(FileAccess.file_exists(PATH), "save written immediately on discovery")
	var reloaded := SaveStore.load_or_new(PATH)
	assert_true(reloaded.is_discovered(&"revette"), "reloaded save has revette")
	_end()

func test_record_does_not_save_without_news() -> void:
	_begin()
	GameState.record(_species(&"revette"))
	_remove_file()
	GameState.record(_species(&"revette")) # 2nd capture: no new species, no detail
	assert_false(FileAccess.file_exists(PATH), "no write when nothing new")
	_end()

func test_finish_night_unlocks_harpoon() -> void:
	_begin()
	for id: StringName in [&"revette", &"nostalgerbe", &"calinette", &"timidelle"]:
		GameState.herbarium.record(_species(id))
	var captures: Array[StringName] = []
	var r := GameState.finish_night(200, false, captures)
	assert_eq(r["unlocked"], [&"harpoon"], "harpoon unlocked")
	assert_eq(int(r["dawn_memory"]), -1, "no memory on an interrupted night")
	assert_eq(int(r["best_minutes"]), 200, "best minutes")
	assert_eq(GameState.last_night, r, "result stored in last_night")
	assert_true(SaveStore.load_or_new(PATH).unlocked_tools.has(&"harpoon"), "saved")
	_end()

func test_finish_full_night_reveals_memory() -> void:
	_begin()
	var captures: Array[StringName] = []
	var r := GameState.finish_night(480, true, captures)
	assert_eq(int(r["dawn_memory"]), 0, "first dawn memory")
	assert_true(bool(r["full"]), "full")
	assert_eq(int(r["minutes"]), 480, "minutes")
	_end()

func test_finish_night_lists_new_species() -> void:
	_begin()
	GameState.herbarium.record(_species(&"revette")) # known before the night
	GameState.begin_night()
	GameState.record(_species(&"revette"))
	GameState.record(_species(&"nostalgerbe"))
	var captures: Array[StringName] = [&"revette", &"nostalgerbe"]
	var r := GameState.finish_night(40, false, captures)
	assert_eq(r["new_species"], [&"nostalgerbe"], "only this night's discoveries")
	assert_eq(r["captures"], [&"revette", &"nostalgerbe"], "captures echoed")
	_end()

func test_capture_minutes_defaults_to_species_reward() -> void:
	var saved := GameState.debug_minutes_multiplier
	GameState.debug_minutes_multiplier = 1
	var revette := _species(&"revette")
	assert_eq(GameState.capture_minutes(revette), revette.minutes_reward(), "multiplier 1 keeps the reward")
	GameState.debug_minutes_multiplier = saved

func test_capture_minutes_applies_debug_multiplier_in_debug_builds() -> void:
	var saved := GameState.debug_minutes_multiplier
	GameState.debug_minutes_multiplier = 24
	var revette := _species(&"revette")
	var expected := revette.minutes_reward() * (24 if OS.is_debug_build() else 1)
	assert_eq(GameState.capture_minutes(revette), expected, "multiplier only in debug builds")
	GameState.debug_minutes_multiplier = saved

func test_parse_multiplier_rejects_invalid_values() -> void:
	assert_eq(GameState.parse_multiplier("24"), 24, "valid integer")
	assert_eq(GameState.parse_multiplier(""), 1, "empty")
	assert_eq(GameState.parse_multiplier("abc"), 1, "not a number")
	assert_eq(GameState.parse_multiplier("0"), 1, "zero clamps to 1")
	assert_eq(GameState.parse_multiplier("-5"), 1, "negative clamps to 1")
