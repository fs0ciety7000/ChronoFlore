extends "res://tests/test_case.gd"

const PATH := "user://test_ui.json"

var _saved_path: String
var _saved_herbarium: Herbarium
var _saved_last: Dictionary

func _begin() -> void:
	_saved_path = GameState.save_path
	_saved_herbarium = GameState.herbarium
	_saved_last = GameState.last_night
	GameState.save_path = PATH
	GameState.herbarium = Herbarium.new()

func _finish() -> void:
	for p in [PATH, PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	GameState.save_path = _saved_path
	GameState.herbarium = _saved_herbarium
	GameState.last_night = _saved_last

func _add(path: String) -> Node:
	var n := (load(path) as PackedScene).instantiate()
	tree.root.add_child(n)
	await tree.process_frame
	return n

func test_clock_flower_state() -> void:
	var f := ClockFlower.new()
	f.set_state(0.5, 3, 5)
	assert_near(f.needle_angle, PI, 0.0001, "half a night points down")
	assert_eq(f.lost, 2, "two petals lost")
	assert_eq(f.label_text, "4 h 00", "label follows progress")
	assert_eq(ClockFlower.format_time(200), "3 h 20", "time format")
	f.set_state(2.0, 9, 5)
	assert_eq(f.lost, 0, "petals clamped")
	assert_near(f.needle_angle, TAU, 0.0001, "progress clamped to a full turn")
	f.free()

func test_wake_texts() -> void:
	_begin()
	GameState.last_night = {"minutes": 200, "full": false, "captures": [&"revette", &"revette"],
		"new_species": [&"revette"], "unlocked": [], "dawn_memory": -1, "best_minutes": 300}
	var w := await _add("res://scenes/ui/wake.tscn")
	assert_true(w.title_label.text.contains("3 h 20"), "sudden wake shows the time")
	assert_true(w.title_label.text.contains("sursaut"), "sudden wake wording")
	assert_true(w.summary_label.text.contains("Rêvette"), "captures listed")
	assert_true(w.summary_label.text.contains("Nouvelle page"), "new page listed")
	assert_true(w.record_label.text.contains("5 h 00"), "record shown")
	assert_true(w.memory_label.text.is_empty(), "no memory on a sudden wake")
	w.free()
	GameState.last_night = {"minutes": 480, "full": true, "captures": [], "new_species": [],
		"unlocked": [&"harpoon"], "dawn_memory": 0, "best_minutes": 480}
	w = await _add("res://scenes/ui/wake.tscn")
	assert_true(w.title_label.text.contains("l'aube"), "full night shows dawn")
	assert_true(w.summary_label.text.contains("Nouvel outil : Harpon"), "unlock shown")
	assert_true(w.memory_label.text.contains("fenêtre"), "dawn memory revealed")
	w.free()
	_finish()

func test_wake_without_result() -> void:
	_begin()
	GameState.last_night = {}
	var w := await _add("res://scenes/ui/wake.tscn")
	assert_true(w.title_label != null, "wake survives an empty result")
	w.free()
	_finish()

func test_herbarium_hides_unknown() -> void:
	_begin()
	var h := await _add("res://scenes/ui/herbarium.tscn")
	h.show_species(&"timidelle")
	assert_eq(h.name_label.text, "???", "unknown page shows ???")
	assert_eq(h.list_buttons.size(), GameState.catalog.species.size(), "every species listed")
	assert_eq(h.list_buttons[2].text, "???", "unknown entries are hidden in the list")
	GameState.herbarium.counts[&"timidelle"] = 5
	h.refresh()
	h.show_species(&"timidelle")
	assert_eq(h.name_label.text, "Timidelle", "discovered page shows the name")
	assert_true(h.details_label.text.contains("Elle ne sort"), "first detail revealed at 5")
	assert_false(h.details_label.text.contains("répète"), "second detail still hidden")
	h.free()
	_finish()

func test_herbarium_memories() -> void:
	_begin()
	GameState.herbarium.next_dawn_memory = 1
	var h := await _add("res://scenes/ui/herbarium.tscn")
	assert_true(h.memories_label.text.contains("fenêtre"), "read memory listed")
	assert_false(h.memories_label.text.contains("carnet"), "unread memory hidden")
	h.show_memories()
	assert_true(h.memories_label.visible and not h.name_label.visible, "memories section replaces the page")
	h.show_species(&"revette")
	assert_true(h.name_label.visible and not h.memories_label.visible, "species page replaces memories")
	h.free()
	_finish()

func test_scenes_instantiate() -> void:
	_begin()
	for path in ["title", "hud", "herbarium", "pause", "wake"]:
		var n := await _add("res://scenes/ui/%s.tscn" % path)
		assert_true(n != null and n.is_inside_tree(), "%s instantiates" % path)
		n.free()
	var main := await _add("res://scenes/main.tscn")
	assert_true(main != null, "main scene instantiates")
	main.free()
	_finish()

func test_title_focus_and_web_quit() -> void:
	var t := await _add("res://scenes/ui/title.tscn")
	assert_true(t.start_button.has_focus(), "first button focused")
	assert_eq(t.quit_button.visible, not OS.has_feature("web"), "quit hidden on web only")
	t.free()

## M12: without persistent storage the title says so in a small cream notice.
func test_title_save_notice() -> void:
	GameState.persistence_override = false
	var t := await _add("res://scenes/ui/title.tscn")
	assert_true(t.save_notice.visible, "notice shown without persistence")
	assert_true((t.save_notice.get_node("Label") as Label).text.contains("Sauvegarde indisponible"), "notice text")
	t.free()
	GameState.persistence_override = true
	var t2 := await _add("res://scenes/ui/title.tscn")
	assert_false(t2.save_notice.visible, "no notice when saves persist")
	t2.free()
	GameState.persistence_override = null
	assert_eq(GameState.persistence_available(), OS.is_userfs_persistent(), "reads the OS by default")

func test_hud_toast_and_tool() -> void:
	_begin()
	var hud := await _add("res://scenes/ui/hud.tscn")
	var rev := GameState.catalog.species_by_id(&"revette")
	hud.show_capture(rev, true)
	assert_true(hud.toast_label.text.contains("+20 min · Rêvette"), "capture toast")
	assert_true(hud.toast_label.text.contains("Nouvelle page !"), "new page toast")
	hud.show_capture(rev, false)
	assert_false(hud.toast_label.text.contains("Nouvelle page"), "no new page toast")
	if OS.is_debug_build(): # the toast shows the minutes the clock really gains
		var saved := GameState.debug_minutes_multiplier
		GameState.debug_minutes_multiplier = 3
		hud.show_capture(rev, false)
		assert_true(hud.toast_label.text.contains("+60 min"), "toast follows capture_minutes (x3)")
		GameState.debug_minutes_multiplier = saved
	hud.set_tool(GameState.catalog.tool_by_id(&"net"))
	assert_true(hud.tool_label.text.length() > 0, "tool shown")
	hud.free()
	_finish()

func test_hud_follows_session() -> void:
	_begin()
	var s := (load("res://scenes/night/night.tscn") as PackedScene).instantiate() as NightSession
	s.auto_change_scene = false
	tree.root.add_child(s)
	await tree.process_frame
	var hud := s.get_node("HUD/Hud")
	s.clock.add_minutes(200)
	assert_eq(hud.flower.label_text, "3 h 20", "clock label follows the session")
	s.lucidity.lose_petal()
	assert_eq(hud.flower.lost, 1, "petal loss shown")
	var belt := s.get_node("Heroine/ToolBelt") as ToolBelt
	belt.cycle(1)
	assert_eq(hud.tool_label.text, belt.current().display_name, "tool cartouche follows the belt")
	var plant := s.add_plant(GameState.catalog.species_by_id(&"revette"), s.island.shape.centroid())
	plant.captured.emit(plant)
	assert_true(hud.toast_label.text.contains("Nouvelle page"), "capture toast with discovery")
	s.free()
	_finish()

func test_pause_flow() -> void:
	_begin()
	var s := (load("res://scenes/night/night.tscn") as PackedScene).instantiate() as NightSession
	s.auto_change_scene = false
	tree.root.add_child(s)
	await tree.process_frame
	s.open_pause()
	await tree.process_frame
	assert_true(tree.paused, "tree paused")
	var menu := s.pause_menu
	assert_eq(menu.process_mode, Node.PROCESS_MODE_ALWAYS, "menu keeps running")
	assert_true(menu.resume_button.has_focus(), "resume focused")
	menu.resume()
	await tree.process_frame
	assert_false(tree.paused, "resumed")
	s.open_pause()
	s.pause_menu.abandon()
	assert_false(tree.paused, "abandon unpauses")
	assert_true(s.ended, "abandon ends the night")
	assert_false(bool(GameState.last_night["full"]), "abandoned night is not full")
	s.free()
	_finish()
