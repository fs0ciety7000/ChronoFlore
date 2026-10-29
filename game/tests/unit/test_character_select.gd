extends "res://tests/test_case.gd"
## Character select, game modes, per-player input actions (Task C2).

const SELECT_SCENE := "res://scenes/ui/character_select.tscn"
const NIGHT_SCENE := "res://scenes/night/night.tscn"
const HEROINE_VISUAL := "res://scenes/heroine/heroine_visual.tscn"
const HERO2_VISUAL := "res://scenes/heroine/hero2_visual.tscn"
const PATH := "user://test_select.json"
## Every per-player action: p1_<base> and p2_<base>. `pause` stays shared (unprefixed).
const BASES := ["move_left", "move_right", "move_up", "move_down", "aim_left", "aim_right",
		"aim_up", "aim_down", "use_tool", "next_tool", "prev_tool", "tool_1", "tool_2", "tool_3"]

var _saved_path: String
var _saved_herbarium: Herbarium
var _saved_mode: GameState.Mode

func _begin() -> void:
	_saved_path = GameState.save_path
	_saved_herbarium = GameState.herbarium
	_saved_mode = GameState.mode
	GameState.save_path = PATH
	GameState.herbarium = Herbarium.new()

func _finish() -> void:
	for p in [PATH, PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	GameState.save_path = _saved_path
	GameState.herbarium = _saved_herbarium
	GameState.mode = _saved_mode

func _select() -> CharacterSelect:
	var cs := (load(SELECT_SCENE) as PackedScene).instantiate() as CharacterSelect
	cs.auto_change_scene = false
	tree.root.add_child(cs)
	await tree.process_frame
	return cs

func _session() -> NightSession:
	var s := (load(NIGHT_SCENE) as PackedScene).instantiate() as NightSession
	s.auto_change_scene = false
	tree.root.add_child(s)
	await tree.process_frame
	return s

func _visual_path(h: Heroine) -> String:
	var v := h.get_node_or_null("Visual")
	return v.scene_file_path if v != null else ""

func test_select_sets_mode() -> void:
	_begin()
	GameState.mode = GameState.Mode.SOLO_HEROINE
	var cs: CharacterSelect = await _select()
	assert_eq(cs.cards.size(), 3, "three cards")
	var chosen: Array = []
	cs.chosen.connect(func(m: GameState.Mode) -> void: chosen.append(m))
	cs.hero_card.pressed.emit()
	assert_eq(GameState.mode, GameState.Mode.SOLO_HERO, "« Lui » -> SOLO_HERO")
	assert_eq(chosen, [GameState.Mode.SOLO_HERO], "chosen emitted once")
	cs.coop_card.pressed.emit()
	assert_eq(GameState.mode, GameState.Mode.COOP, "« À deux » -> COOP")
	cs.heroine_card.pressed.emit()
	assert_eq(GameState.mode, GameState.Mode.SOLO_HEROINE, "« Elle » -> SOLO_HEROINE")
	for card: Button in cs.cards:
		var thumb := card.find_child("Thumb", true, false) as TextureRect
		assert_true(thumb != null and thumb.texture != null, card.name + " has a thumbnail")
	cs.free()
	_finish()

func test_select_keyboard_navigation() -> void:
	_begin()
	GameState.mode = GameState.Mode.SOLO_HEROINE
	var cs: CharacterSelect = await _select()
	assert_true(cs.heroine_card.has_focus(), "current mode's card focused")
	assert_eq(cs.heroine_card.get_node(cs.heroine_card.focus_neighbor_right), cs.hero_card, "right -> Lui")
	assert_eq(cs.hero_card.get_node(cs.hero_card.focus_neighbor_right), cs.coop_card, "right -> À deux")
	assert_eq(cs.coop_card.get_node(cs.coop_card.focus_neighbor_left), cs.hero_card, "left -> Lui")
	assert_eq(cs.heroine_card.get_node(cs.heroine_card.focus_neighbor_bottom), cs.back_button, "down -> Retour")
	cs.free()
	_finish()

func test_solo_hero_spawns_hero_visual() -> void:
	_begin()
	GameState.mode = GameState.Mode.SOLO_HERO
	var s: NightSession = await _session()
	assert_eq(s.players.size(), 1, "one player")
	assert_true(s.players[0] == s.heroine, "the player is the session's main character node")
	assert_eq(s.players[0].player_index, 0, "player index 0")
	assert_eq(_visual_path(s.players[0]), HERO2_VISUAL, "hero visual")
	assert_eq(s.players[0].get_node("Visual").get_child_count() > 0, true, "visual built")
	s.free()
	_finish()

func test_solo_heroine_default() -> void:
	var fresh: Node = load("res://scripts/autoload/game_state.gd").new()
	assert_eq(fresh.mode, GameState.Mode.SOLO_HEROINE, "default mode is the heroine alone")
	fresh.free()
	_begin()
	GameState.mode = GameState.Mode.SOLO_HEROINE
	var s: NightSession = await _session()
	assert_eq(s.players.size(), 1, "one player")
	assert_eq(_visual_path(s.players[0]), HEROINE_VISUAL, "heroine visual")
	# Re-setup is idempotent and swaps the visual in place.
	s.setup_players(GameState.Mode.SOLO_HERO)
	assert_eq(s.players.size(), 1, "still one player")
	assert_eq(_visual_path(s.players[0]), HERO2_VISUAL, "visual swapped")
	assert_eq(s.get_tree().get_nodes_in_group("heroine").size(), 1, "no stray player")
	s.free()
	_finish()

func test_coop_spawns_two_players() -> void:
	_begin()
	GameState.mode = GameState.Mode.COOP
	var s: NightSession = await _session()
	assert_eq(s.players.size(), 2, "two players")
	assert_eq(_visual_path(s.players[0]), HEROINE_VISUAL, "P1 is the heroine")
	assert_eq(_visual_path(s.players[1]), HERO2_VISUAL, "P2 is the hero")
	assert_eq(s.players[1].player_index, 1, "P2 index")
	assert_true(s.players[1].lucidity == s.lucidity, "shared lucidity")
	assert_true(s.players[1].get_node("ToolBelt") != s.players[0].get_node("ToolBelt"), "own tool belt")
	s.setup_players(GameState.Mode.SOLO_HEROINE)
	await tree.process_frame
	assert_eq(s.players.size(), 1, "back to one player")
	assert_eq(s.get_tree().get_nodes_in_group("heroine").size(), 1, "P2 removed")
	s.free()
	_finish()

## Review Focus 5: the mode survives a trip back to the title, and the select screen shows it.
func test_mode_persists_after_title() -> void:
	_begin()
	GameState.mode = GameState.Mode.SOLO_HEROINE
	var cs: CharacterSelect = await _select()
	cs.choose(GameState.Mode.SOLO_HERO)
	cs.free()
	var title := (load("res://scenes/ui/title.tscn") as PackedScene).instantiate() as TitleScreen
	tree.root.add_child(title)
	await tree.process_frame
	assert_eq(GameState.mode, GameState.Mode.SOLO_HERO, "title keeps the mode")
	title.free()
	cs = await _select()
	assert_true(cs.hero_card.has_focus(), "select screen shows the kept mode")
	cs.go_back()
	assert_eq(GameState.mode, GameState.Mode.SOLO_HERO, "back without choosing keeps the mode")
	cs.free()
	var s: NightSession = await _session() # what "Nuit suivante" / start_night() opens
	assert_eq(_visual_path(s.players[0]), HERO2_VISUAL, "next night replays the hero")
	s.free()
	_finish()

func test_input_actions_prefixed() -> void:
	for base: String in BASES:
		for prefix in ["p1_", "p2_"]:
			var action: String = prefix + base
			assert_true(InputMap.has_action(action), "has " + action)
			if InputMap.has_action(action):
				assert_true(InputMap.action_get_events(action).size() >= 1, action + " has events")
		assert_false(InputMap.has_action(base), base + " renamed")
	assert_true(InputMap.has_action("pause"), "pause stays shared")

func test_heroine_actions_follow_player_index() -> void:
	var h := (load("res://scenes/heroine/heroine.tscn") as PackedScene).instantiate() as Heroine
	assert_eq(h.action(&"use_tool"), &"p1_use_tool", "index 0 -> p1_")
	h.player_index = 1
	assert_eq(h.action(&"move_left"), &"p2_move_left", "index 1 -> p2_")
	h.free()

## Only the heroine dreams: after a night played as the hero, the wake screen still speaks of her.
func test_wake_speaks_of_her_after_hero_night() -> void:
	_begin()
	var saved_last := GameState.last_night
	GameState.mode = GameState.Mode.SOLO_HERO
	GameState.last_night = {"minutes": 130, "full": false, "captures": [], "best_minutes": 130}
	var w := (load("res://scenes/ui/wake.tscn") as PackedScene).instantiate() as WakeScreen
	tree.root.add_child(w)
	await tree.process_frame
	assert_true(w.title_label.text.begins_with("Elle se réveille"), "wake text speaks of her")
	w.free()
	GameState.last_night = saved_last
	_finish()
