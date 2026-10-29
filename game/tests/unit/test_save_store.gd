extends "res://tests/test_case.gd"

const PATH := "user://test_save.json"

func _cleanup() -> void:
	for p in [PATH, PATH + ".bak", PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func _write(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func test_save_store_roundtrip() -> void:
	_cleanup()
	var h := Herbarium.new()
	h.counts[&"revette"] = 7
	h.unlocked_tools.append(&"harpoon")
	h.best_minutes = 123
	h.full_nights = 2
	h.next_dawn_memory = 2
	assert_eq(SaveStore.save(h, PATH), OK, "save ok")
	var h2 := SaveStore.load_or_new(PATH)
	assert_eq(h2.counts, {&"revette": 7}, "counts")
	assert_eq(h2.unlocked_tools, [&"harpoon"] as Array[StringName], "tools")
	assert_eq(h2.best_minutes, 123, "best")
	assert_eq(h2.full_nights, 2, "full nights")
	assert_eq(h2.next_dawn_memory, 2, "memory")
	_cleanup()

func test_save_store_missing() -> void:
	_cleanup()
	var h := SaveStore.load_or_new(PATH)
	assert_true(h != null, "not null")
	assert_eq(h.counts.size(), 0, "fresh")
	assert_false(FileAccess.file_exists(PATH + ".bak"), "no bak for missing")

func test_save_store_corrupt() -> void:
	_cleanup()
	_write("{not json")
	var h := SaveStore.load_or_new(PATH)
	assert_eq(h.counts.size(), 0, "corrupt -> fresh")
	assert_true(FileAccess.file_exists(PATH + ".bak"), "bak written")
	assert_eq(FileAccess.get_file_as_string(PATH + ".bak"), "{not json", "bak content")
	_cleanup()
	_write('{"version": 99}')
	var h2 := SaveStore.load_or_new(PATH)
	assert_eq(h2.counts.size(), 0, "unknown version -> fresh")
	assert_true(FileAccess.file_exists(PATH + ".bak"), "bak for unknown version")
	_cleanup()
