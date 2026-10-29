extends "res://tests/test_case.gd"

func _catalog() -> GameCatalog:
	return load("res://data/catalog.tres") as GameCatalog

func _sp(id: StringName) -> PlantSpecies:
	return _catalog().species_by_id(id)

func test_record_new_species() -> void:
	var h := Herbarium.new()
	assert_false(h.is_discovered(&"revette"), "undiscovered")
	var r := h.record(_sp(&"revette"))
	assert_eq(r, {"new_species": true, "new_detail": -1}, "first record")
	assert_true(h.is_discovered(&"revette"), "discovered")
	assert_eq(h.record(_sp(&"revette"))["new_species"], false, "second not new")

func test_detail_thresholds() -> void:
	var h := Herbarium.new()
	var rev := _sp(&"revette")
	for i in 4:
		h.record(rev)
	assert_eq(h.revealed_details(&"revette"), 0, "0 details after 4")
	assert_eq(h.record(rev)["new_detail"], 0, "5th reveals detail 0")
	assert_eq(h.revealed_details(&"revette"), 1, "1 detail after 5")
	for i in 9:
		assert_eq(h.record(rev)["new_detail"], -1, "no detail between")
	assert_eq(h.record(rev)["new_detail"], 1, "15th reveals detail 1")
	assert_eq(h.revealed_details(&"revette"), 2, "2 details after 15")
	assert_eq(h.record(rev)["new_detail"], -1, "16th none")

func test_ronce_counts_but_not_toward_milestone() -> void:
	var c := _catalog()
	var h := Herbarium.new()
	h.record(_sp(&"revette"))
	h.record(_sp(&"nostalgerbe"))
	var r := h.record(_sp(&"ronce_angoisse"))
	assert_true(r["new_species"], "ronce page discovered")
	assert_eq(h.discovered_capturable_count(c), 2, "2 capturable")
	assert_eq(h.apply_milestones(c), [] as Array[StringName], "no unlock yet")
	h.record(_sp(&"timidelle"))
	assert_eq(h.apply_milestones(c), [&"harpoon"] as Array[StringName], "harpoon unlocked")
	assert_eq(h.apply_milestones(c), [] as Array[StringName], "only once")

func test_available_tools() -> void:
	var c := _catalog()
	var h := Herbarium.new()
	assert_eq(h.available_tools(c), [&"net", &"tranquilizer"] as Array[StringName], "defaults")
	h.unlocked_tools.append(&"harpoon")
	assert_eq(h.available_tools(c), [&"net", &"tranquilizer", &"harpoon"] as Array[StringName], "all")

func test_register_night() -> void:
	var c := _catalog()
	var h := Herbarium.new()
	assert_eq(h.register_night(300, false, c), -1, "short night")
	assert_eq(h.best_minutes, 300, "best 300")
	assert_eq(h.full_nights, 0, "no full night")
	assert_eq(h.register_night(480, true, c), 0, "memory 0")
	assert_eq(h.register_night(480, true, c), 1, "memory 1")
	assert_eq(h.register_night(480, true, c), 2, "memory 2")
	assert_eq(h.register_night(480, true, c), -1, "all read")
	assert_eq(h.full_nights, 4, "4 full nights")
	assert_eq(h.best_minutes, 480, "best 480")
	assert_eq(h.next_dawn_memory, 3, "index stops at 3")

func test_roundtrip() -> void:
	var c := _catalog()
	var h := Herbarium.new()
	h.record(_sp(&"revette"))
	h.record(_sp(&"revette"))
	h.record(_sp(&"ronce_angoisse"))
	h.unlocked_tools.append(&"harpoon")
	h.register_night(480, true, c)
	# Go through real JSON so numbers come back as floats.
	var parsed: Variant = JSON.parse_string(JSON.stringify(h.to_dict()))
	var h2 := Herbarium.from_dict(parsed)
	assert_true(h2 != null, "from_dict ok")
	assert_eq(h2.counts, {&"revette": 2, &"ronce_angoisse": 1}, "counts")
	assert_eq(h2.unlocked_tools, [&"harpoon"] as Array[StringName], "tools")
	assert_eq(h2.best_minutes, 480, "best")
	assert_eq(h2.full_nights, 1, "full nights")
	assert_eq(h2.next_dawn_memory, 1, "next memory")

func test_from_dict_invalid() -> void:
	assert_true(Herbarium.from_dict({}) == null, "empty")
	assert_true(Herbarium.from_dict({"version": 2}) == null, "wrong version")
	assert_true(Herbarium.from_dict({"version": 1, "counts": "x", "unlocked_tools": [], "best_minutes": 0, "full_nights": 0, "next_dawn_memory": 0}) == null, "bad counts")
