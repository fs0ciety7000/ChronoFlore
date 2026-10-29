extends "res://tests/test_case.gd"
## Tool switching in a real night through real InputEvents (pushed into the viewport), and the
## HUD tool bar: one slot per tool, locked harpoon padlocked with its species count.

const NIGHT_SCENE := "res://scenes/night/night.tscn"
const PATH := "user://test_tool_switching.json"

var _saved_path: String
var _saved_herbarium: Herbarium
var _saved_hint: bool

func _session(herbarium: Herbarium = Herbarium.new()) -> NightSession:
	_saved_path = GameState.save_path
	_saved_herbarium = GameState.herbarium
	_saved_hint = GameState.tool_hint_shown
	GameState.save_path = PATH
	GameState.herbarium = herbarium
	GameState.mode = GameState.Mode.SOLO_HEROINE
	var s := (load(NIGHT_SCENE) as PackedScene).instantiate() as NightSession
	s.auto_change_scene = false
	tree.root.add_child(s)
	await tree.process_frame
	return s

func _end(s: NightSession) -> void:
	s.free()
	for p in [PATH, PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	GameState.save_path = _saved_path
	GameState.herbarium = _saved_herbarium
	GameState.tool_hint_shown = _saved_hint

func _press(e: InputEvent) -> void:
	tree.root.push_input(e)
	var up := e.duplicate() as InputEvent
	up.set("pressed", false)
	tree.root.push_input(up)

## AZERTY top row: physical 1/2/3 send & é " as keycodes.
func _key(physical: Key, keycode: int, unicode: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = physical
	e.keycode = keycode as Key
	e.unicode = unicode
	e.pressed = true
	return e

func _wheel(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.factor = 1.0
	return e

func _pad(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	e.device = 0
	return e

func test_night_starts_with_net_and_tranquilizer() -> void:
	var s: NightSession = await _session()
	var belt := s.heroine.get_node("ToolBelt") as ToolBelt
	assert_eq(belt.tools.size(), 2, "net and tranquilizer from the start")
	assert_eq(belt.current().id, &"net", "net first")
	_end(s)

func test_switching_with_real_input_events() -> void:
	var s: NightSession = await _session()
	var belt := s.heroine.get_node("ToolBelt") as ToolBelt
	var visual := s.heroine.get_node("Visual")
	_press(_key(KEY_2, 0xE9, 0xE9))
	assert_eq(belt.current().id, &"tranquilizer", "AZERTY 2 (é) selects the tranquilizer")
	assert_eq(visual.call("shown_tool_prop"), "DartGun", "dart gun in hand")
	assert_eq(s.hud.tool_bar.selected_index(), 1, "tool bar highlights slot 2")
	_press(_key(KEY_1, KEY_AMPERSAND, 0x26))
	assert_eq(belt.current().id, &"net", "AZERTY 1 (&) selects the net")
	_press(_key(KEY_3, KEY_QUOTEDBL, 0x22))
	assert_eq(belt.current().id, &"net", "3: harpoon still locked")
	_press(_key(KEY_R, KEY_R, 0x72))
	assert_eq(belt.current().id, &"tranquilizer", "R cycles")
	_press(_wheel(MOUSE_BUTTON_WHEEL_UP))
	assert_eq(belt.current().id, &"net", "wheel up cycles back")
	_press(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	assert_eq(belt.current().id, &"tranquilizer", "wheel down cycles")
	_press(_pad(JOY_BUTTON_LEFT_SHOULDER))
	assert_eq(belt.current().id, &"net", "LB cycles back")
	_press(_pad(JOY_BUTTON_RIGHT_SHOULDER))
	assert_eq(belt.current().id, &"tranquilizer", "RB cycles")
	_end(s)

func test_tool_bar_shows_the_locked_harpoon() -> void:
	var s: NightSession = await _session()
	var bar: ToolBar = s.hud.tool_bar
	assert_eq(bar.slots.size(), 3, "three slots")
	assert_false(bar.is_locked(0), "net unlocked")
	assert_false(bar.is_locked(1), "tranquilizer unlocked")
	assert_true(bar.is_locked(2), "harpoon locked")
	assert_true((bar.slots[2]["lock"] as Control).visible, "padlock shown")
	assert_eq(bar.slot_hint(2), "4 espèces", "unlock requirement shown")
	assert_eq(bar.slot_hint(0), "[1]", "keyboard hint")
	assert_eq(bar.slot_hint(1), "[2]", "keyboard hint")
	assert_eq(bar.selected_index(), 0, "net highlighted")
	s.hud.set_pad_mode(true)
	assert_eq(bar.slot_hint(0), "LB / RB", "pad hint on the selected slot")
	s.hud.set_pad_mode(false)
	assert_eq(bar.slot_hint(0), "[1]", "back to keyboard hints")
	_end(s)

func test_pad_input_switches_hints() -> void:
	var s: NightSession = await _session()
	_press(_pad(JOY_BUTTON_A))
	assert_true(s.hud.pad_mode, "a pad button switches to pad hints")
	_press(_key(KEY_W, KEY_Z, 0x7A))
	assert_false(s.hud.pad_mode, "a key switches back")
	_end(s)

func test_unlocked_harpoon_has_its_slot() -> void:
	var herb := Herbarium.new()
	herb.unlocked_tools.append(&"harpoon")
	var s: NightSession = await _session(herb)
	var belt := s.heroine.get_node("ToolBelt") as ToolBelt
	assert_false(s.hud.tool_bar.is_locked(2), "harpoon slot open")
	_press(_key(KEY_3, KEY_QUOTEDBL, 0x22))
	assert_eq(belt.current().id, &"harpoon", "3 selects the harpoon")
	assert_eq(s.hud.tool_bar.slot_hint(2), "[3]", "key hint")
	_end(s)

func test_first_night_hint_once() -> void:
	GameState.tool_hint_shown = false
	var s: NightSession = await _session()
	assert_true(s.hud.tool_hint.visible, "hint on the first night")
	assert_true(s.hud.hint_label.text.contains("1-2-3"), "keyboard wording")
	var belt := s.heroine.get_node("ToolBelt") as ToolBelt
	belt.cycle(1)
	await tree.create_timer(0.6).timeout
	assert_false(s.hud.tool_hint.visible, "gone after the first switch")
	var keep := _saved_hint
	s.free()
	var s2: NightSession = await _session()
	assert_false(s2.hud.tool_hint.visible, "not shown again")
	_end(s2)
	GameState.tool_hint_shown = keep
