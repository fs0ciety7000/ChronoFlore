extends "res://tests/test_case.gd"
## The 12-species herbarium (Task B4): catalog texts, old saves, milestone, page scrolling.
## Never touches user://save.json: GameState is pointed at a test path.

const PATH := "user://test_bestiary_herbarium.json"

var _saved_path: String
var _saved_herbarium: Herbarium

func _begin() -> void:
	_saved_path = GameState.save_path
	_saved_herbarium = GameState.herbarium
	GameState.save_path = PATH
	GameState.herbarium = Herbarium.new()

func _finish() -> void:
	for p in [PATH, PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	GameState.save_path = _saved_path
	GameState.herbarium = _saved_herbarium

func _add(path: String) -> Node:
	var n := (load(path) as PackedScene).instantiate()
	tree.root.add_child(n)
	await tree.process_frame
	return n

func _action(name: StringName) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev

func test_catalog_has_12_species() -> void:
	var c := GameState.catalog
	assert_eq(c.species.size(), 12, "12 species")
	var hostile := 0
	var gentle := 0
	for s in c.species:
		if s.hostile:
			hostile += 1
		else:
			gentle += 1
		assert_true(s.visual_scene != null, "%s has a model" % s.id)
		assert_true(s.display_name != "" and s.emotion != "", "%s has a name and an emotion" % s.id)
		assert_true(s.fragment.begins_with("(provisoire) "), "%s fragment is provisional French" % s.id)
		assert_eq(s.details.size(), 2, "%s has exactly 2 details" % s.id)
		for d in s.details:
			assert_true(d.begins_with("(provisoire) "), "%s detail is provisional" % s.id)
		assert_true(ResourceLoader.exists(HerbariumScreen.thumb_path(s.id, true)), "%s thumbnail" % s.id)
		assert_true(ResourceLoader.exists(HerbariumScreen.thumb_path(s.id, false)), "%s silhouette" % s.id)
	assert_eq(gentle, 7, "7 gentle species")
	assert_eq(hostile, 5, "5 hostile species")

func test_old_save_loads_with_new_catalog() -> void:
	_begin()
	var old := {"version": 1, "counts": {"revette": 6, "nostalgerbe": 1, "timidelle": 5, "ronce_angoisse": 2},
		"unlocked_tools": ["harpoon"], "best_minutes": 200, "full_nights": 1, "next_dawn_memory": 1}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	GameState.load_save()
	var c := GameState.catalog
	var known := 0
	var unknown := 0
	for s in c.species:
		if GameState.herbarium.is_discovered(s.id):
			known += 1
		else:
			unknown += 1
	assert_eq(known, 4, "4 pages discovered")
	assert_eq(unknown, 8, "8 pages unknown")
	var h := await _add("res://scenes/ui/herbarium.tscn")
	assert_eq(h.list_buttons.size(), 12, "12 list entries")
	h.show_species(&"champi_panique")
	assert_eq(h.name_label.text, "???", "new page is simply unknown")
	h.show_species(&"revette")
	assert_eq(h.name_label.text, "Rêvette", "old page still readable")
	h.free()
	_finish()

func test_harpoon_milestone_counts_captured_hostiles() -> void:
	var c := GameState.catalog
	var h := Herbarium.new()
	h.record(c.species_by_id(&"revette"))
	h.record(c.species_by_id(&"calinette"))
	assert_eq(h.apply_milestones(c), [] as Array[StringName], "2 species: no harpoon")
	h.record(c.species_by_id(&"croque_colere")) # a hostile, captured asleep
	assert_eq(h.apply_milestones(c), [&"harpoon"] as Array[StringName], "3 captured species unlock the harpoon")
	assert_true(h.available_tools(c).has(&"harpoon"), "harpoon available")

func test_hostile_page_counts_captures() -> void:
	_begin()
	GameState.herbarium.counts[&"croque_colere"] = 2
	var h := await _add("res://scenes/ui/herbarium.tscn")
	h.show_species(&"croque_colere")
	assert_true(h.count_label.text.contains("Captures : 2"), "hostile shows captures")
	assert_false(h.count_label.text.contains("Endormie"), "no sleep wording in the count")
	assert_true(h.details_label.text.contains("à 5 captures"), "locked detail counts captures")
	assert_false(h.details_label.text.contains("sommeil"), "no sleep wording")
	h.free()
	_finish()

func test_herbarium_page_scrolls_with_keyboard() -> void:
	_begin()
	GameState.herbarium.counts[&"revette"] = 20
	var h := await _add("res://scenes/ui/herbarium.tscn")
	h.show_species(&"revette")
	# Force an overflowing page whatever the window size.
	var filler := Control.new()
	filler.custom_minimum_size = Vector2(0, 3000)
	h.page_box.add_child(filler)
	await tree.process_frame
	await tree.process_frame
	assert_eq(h.page_scroll.scroll_vertical, 0, "starts on top")
	# From the list, ui_down moves the list focus: the page must not scroll.
	h.list_buttons[0].grab_focus()
	h._unhandled_input(_action(&"ui_page_down"))
	assert_true(h.page_scroll.scroll_vertical > 0, "page down scrolls even from the list")
	h.page_scroll.scroll_vertical = 0
	h.page_scroll.grab_focus()
	h._unhandled_input(_action(&"ui_down"))
	assert_true(h.page_scroll.scroll_vertical > 0, "ui_down scrolls the focused page")
	var after_down: int = h.page_scroll.scroll_vertical
	h._unhandled_input(_action(&"ui_up"))
	assert_true(h.page_scroll.scroll_vertical < after_down, "ui_up scrolls back")
	h.scroll_page_by(-100000.0)
	assert_eq(h.page_scroll.scroll_vertical, 0, "clamped at top")
	# ui_left returns to the list, on the entry of the page shown.
	h.page_scroll.grab_focus()
	tree.root.push_input(_action(&"ui_left"))
	var revette := GameState.catalog.species.find(GameState.catalog.species_by_id(&"revette"))
	assert_true(h.list_buttons[revette].has_focus(), "ui_left gives the focus back to the list entry")
	# Selecting another species resets to the top.
	h.page_scroll.scroll_vertical = 500
	h.show_species(&"nostalgerbe")
	assert_eq(h.page_scroll.scroll_vertical, 0, "new page starts on top")
	h.free()
	_finish()

func test_embedded_herbarium_closes_on_pause_action() -> void:
	_begin()
	var h := (load("res://scenes/ui/herbarium.tscn") as PackedScene).instantiate() as HerbariumScreen
	h.embedded = true
	var closed_count := [0]
	h.closed.connect(func() -> void: closed_count[0] += 1)
	tree.root.add_child(h)
	await tree.process_frame
	h._unhandled_input(_action(&"pause"))
	assert_eq(closed_count[0], 1, "pause closes the embedded herbarium")
	_finish()

func test_list_scrolls_and_fits_720p() -> void:
	_begin()
	var h := await _add("res://scenes/ui/herbarium.tscn")
	assert_true(h.list_scroll != null, "list sits in a scroll container")
	# The list is inside a scroll area: the screen never needs more than the viewport.
	assert_true(h.list_scroll.size.y <= 720.0, "list area fits 720p")
	h.list_buttons[11].grab_focus()
	await tree.process_frame
	assert_true(h.list_buttons[11].has_focus(), "last entry focusable")
	h.free()
	_finish()
