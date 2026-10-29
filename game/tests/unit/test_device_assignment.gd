extends "res://tests/test_case.gd"
## Task C3: who plays with which device (assignment rules, unplug fallback, InputMap rebuild).

const KBM := DeviceAssignment.Kind.KEYBOARD_MOUSE
const LEFT := DeviceAssignment.Kind.KEYBOARD_LEFT
const RIGHT := DeviceAssignment.Kind.KEYBOARD_RIGHT
const PAD := DeviceAssignment.Kind.PAD

func _pads(ids: Array) -> Array[int]:
	var out: Array[int] = []
	for i in ids:
		out.append(int(i))
	return out

func _kinds(a: Array[Dictionary]) -> Array:
	var out: Array = []
	for d in a:
		out.append([int(d["kind"]), int(d["device"])])
	return out

func _key(physical: Key, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = physical
	e.location = location
	e.pressed = true
	return e

func _stick(device: int, axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = value
	return e

func _button(device: int, button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = true
	return e

func _click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e

func _restore() -> void:
	InputMap.load_from_project_settings()

# --- assignment rules --------------------------------------------------------------------------

func test_solo_any_pads() -> void:
	for ids in [[], [0], [0, 1], [3, 1]]:
		var a := DeviceAssignment.assign(_pads(ids), false)
		assert_eq(_kinds(a), [[KBM, DeviceAssignment.ALL_PADS]], "solo with %s pads: keyboard-mouse + any pad" % [ids])

func test_coop_no_pad_shares_the_keyboard() -> void:
	var a := DeviceAssignment.assign(_pads([]), true)
	assert_eq(_kinds(a), [[LEFT, DeviceAssignment.NO_PAD], [RIGHT, DeviceAssignment.NO_PAD]], "ZQSD/WASD | arrows")

func test_coop_one_pad_goes_to_p2() -> void:
	var a := DeviceAssignment.assign(_pads([2]), true)
	assert_eq(_kinds(a), [[KBM, DeviceAssignment.NO_PAD], [PAD, 2]], "P1 keyboard-mouse, P2 the pad")

func test_coop_two_pads() -> void:
	assert_eq(_kinds(DeviceAssignment.assign(_pads([0, 1]), true)), [[PAD, 0], [PAD, 1]], "pad 0 P1, pad 1 P2")
	assert_eq(_kinds(DeviceAssignment.assign(_pads([4, 1, 7]), true)), [[PAD, 1], [PAD, 4]], "lowest ids first")

func test_auto_aim_kinds() -> void:
	assert_true(DeviceAssignment.auto_aim(LEFT), "left half aims AUTO")
	assert_true(DeviceAssignment.auto_aim(RIGHT), "right half aims AUTO")
	assert_false(DeviceAssignment.auto_aim(KBM), "mouse aims")
	assert_false(DeviceAssignment.auto_aim(PAD), "stick aims")
	assert_true(DeviceAssignment.uses_mouse(KBM), "only keyboard-mouse reads the mouse")
	assert_false(DeviceAssignment.uses_mouse(LEFT), "left half: no mouse")

# --- unplug / plug (Review Focus 1) ------------------------------------------------------------

func test_reassign_p1_pad_unplugged() -> void:
	var a := DeviceAssignment.assign(_pads([0, 1]), true)
	var b := DeviceAssignment.reassign(a, _pads([1]), true)
	assert_eq(_kinds(b), [[LEFT, DeviceAssignment.NO_PAD], [PAD, 1]], "P1 falls back on its keyboard half, P2 keeps its pad")

func test_reassign_p2_pad_unplugged() -> void:
	var a := DeviceAssignment.assign(_pads([0, 1]), true)
	var b := DeviceAssignment.reassign(a, _pads([0]), true)
	assert_eq(_kinds(b), [[PAD, 0], [RIGHT, DeviceAssignment.NO_PAD]], "P2 falls back on the arrows, P1 keeps pad 0")

func test_reassign_single_pad_unplugged() -> void:
	var a := DeviceAssignment.assign(_pads([0]), true)
	var b := DeviceAssignment.reassign(a, _pads([]), true)
	assert_eq(_kinds(b), [[LEFT, DeviceAssignment.NO_PAD], [RIGHT, DeviceAssignment.NO_PAD]], "both on the shared keyboard")

func test_reassign_pad_plugged_back() -> void:
	var a := DeviceAssignment.reassign(DeviceAssignment.assign(_pads([0, 1]), true), _pads([1]), true)
	var b := DeviceAssignment.reassign(a, _pads([0, 1]), true)
	assert_eq(_kinds(b), [[PAD, 0], [PAD, 1]], "P1 picks the new pad up")
	var c := DeviceAssignment.reassign(DeviceAssignment.assign(_pads([]), true), _pads([5]), true)
	assert_eq(_kinds(c), [[KBM, DeviceAssignment.NO_PAD], [PAD, 5]], "first pad goes to P2")

func test_reassign_solo_or_fresh() -> void:
	var empty: Array[Dictionary] = []
	assert_eq(_kinds(DeviceAssignment.reassign(empty, _pads([0]), true)), [[KBM, DeviceAssignment.NO_PAD], [PAD, 0]], "no previous: fresh")
	assert_eq(_kinds(DeviceAssignment.reassign(DeviceAssignment.assign(_pads([0]), false), _pads([]), false)),
			[[KBM, DeviceAssignment.ALL_PADS]], "solo never changes")

# --- runtime filtering: event -> player --------------------------------------------------------

func test_solo_bindings_match_the_project() -> void:
	DeviceAssignment.apply(DeviceAssignment.assign(_pads([]), false))
	assert_eq(DeviceAssignment.player_for_event(_key(KEY_W)), 0, "W -> P1")
	assert_eq(DeviceAssignment.player_for_event(_key(KEY_UP)), 0, "arrows -> P1 in solo")
	assert_eq(DeviceAssignment.player_for_event(_stick(3, JOY_AXIS_LEFT_X, 1.0)), 0, "any pad -> P1 in solo")
	assert_eq(DeviceAssignment.player_for_event(_click()), 0, "mouse -> P1")
	_restore()

func test_shared_keyboard_split() -> void:
	DeviceAssignment.apply(DeviceAssignment.assign(_pads([]), true))
	assert_eq(DeviceAssignment.player_for_event(_key(KEY_W)), 0, "W -> P1")
	assert_eq(DeviceAssignment.player_for_event(_key(KEY_A)), 0, "A (Q on AZERTY) -> P1")
	assert_eq(DeviceAssignment.player_for_event(_key(KEY_F)), 0, "F -> P1 tool")
	assert_true(InputMap.event_is_action(_key(KEY_F), &"p1_use_tool"), "F uses P1's tool")
	assert_true(InputMap.event_is_action(_key(KEY_R), &"p1_next_tool"), "R cycles P1's tool")
	assert_eq(DeviceAssignment.player_for_event(_key(KEY_UP)), 1, "arrows -> P2 only")
	assert_false(InputMap.event_is_action(_key(KEY_LEFT), &"p1_move_left"), "arrows no longer move P1")
	assert_true(InputMap.event_is_action(_key(KEY_ENTER), &"p2_use_tool"), "Enter -> P2 tool")
	assert_true(InputMap.event_is_action(_key(KEY_KP_0), &"p2_use_tool"), "keypad 0 -> P2 tool")
	assert_true(InputMap.event_is_action(_key(KEY_PERIOD), &"p2_next_tool"), "Period -> P2 next tool")
	assert_true(InputMap.event_is_action(_key(KEY_KP_PERIOD), &"p2_next_tool"), "keypad period -> P2 next tool")
	assert_eq(DeviceAssignment.player_for_event(_key(KEY_ENTER)), 1, "Enter is P2's only")
	assert_eq(DeviceAssignment.player_for_event(_key(KEY_PERIOD)), 1, "Period is P2's only")
	assert_eq(DeviceAssignment.player_for_event(_stick(0, JOY_AXIS_LEFT_X, 1.0)), -1, "no pad bound")
	assert_eq(DeviceAssignment.player_for_event(_click()), -1, "nobody reads the mouse")
	_restore()

## Web: a held modifier turns P1's W/Q/Z into Ctrl+W (close tab) or Ctrl+Q; Shift x5 opens
## Sticky Keys on Windows. P2's keys must never be modifiers.
func test_p2_keys_are_not_modifiers() -> void:
	var modifiers: Array[int] = [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]
	for base in DeviceAssignment.BASES:
		for e in DeviceAssignment.events_for(base, RIGHT, DeviceAssignment.NO_PAD):
			var k := e as InputEventKey
			assert_true(k != null and not modifiers.has(int(k.physical_keycode)), "p2_%s key %s is not a modifier" % [base, e])

func test_one_pad_split() -> void:
	DeviceAssignment.apply(DeviceAssignment.assign(_pads([0]), true))
	assert_eq(DeviceAssignment.player_for_event(_key(KEY_UP)), 0, "keyboard (arrows too) -> P1")
	assert_eq(DeviceAssignment.player_for_event(_click()), 0, "mouse -> P1")
	assert_eq(DeviceAssignment.player_for_event(_stick(0, JOY_AXIS_LEFT_X, 1.0)), 1, "pad 0 -> P2")
	assert_true(InputMap.event_is_action(_stick(0, JOY_AXIS_TRIGGER_RIGHT, 1.0), &"p2_use_tool"), "RT -> P2 tool")
	assert_true(InputMap.event_is_action(_stick(0, JOY_AXIS_RIGHT_X, 1.0), &"p2_aim_right"), "right stick -> P2 aim")
	assert_false(InputMap.event_is_action(_stick(0, JOY_AXIS_LEFT_X, 1.0), &"p1_move_right"), "pad 0 no longer moves P1")
	assert_eq(DeviceAssignment.player_for_event(_stick(1, JOY_AXIS_LEFT_X, 1.0)), -1, "pad 1 unbound")
	_restore()

func test_two_pads_split() -> void:
	DeviceAssignment.apply(DeviceAssignment.assign(_pads([0, 1]), true))
	assert_eq(DeviceAssignment.player_for_event(_stick(0, JOY_AXIS_LEFT_Y, -1.0)), 0, "pad 0 -> P1")
	assert_eq(DeviceAssignment.player_for_event(_stick(1, JOY_AXIS_LEFT_Y, -1.0)), 1, "pad 1 -> P2")
	assert_eq(DeviceAssignment.player_for_event(_button(1, JOY_BUTTON_RIGHT_SHOULDER)), 1, "RB pad 1 -> P2")
	assert_true(InputMap.event_is_action(_button(0, JOY_BUTTON_RIGHT_SHOULDER), &"p1_next_tool"), "RB pad 0 -> P1 next tool")
	assert_true(InputMap.has_action(&"pause"), "pause untouched")
	assert_true(InputMap.event_is_action(_button(1, JOY_BUTTON_START), &"pause"), "any pad pauses")
	_restore()

func test_unplugged_player_moves_on_keyboard() -> void:
	var a := DeviceAssignment.reassign(DeviceAssignment.assign(_pads([0, 1]), true), _pads([1]), true)
	DeviceAssignment.apply(a)
	assert_eq(DeviceAssignment.player_for_event(_key(KEY_W)), 0, "P1 walks with W after losing pad 0")
	assert_eq(DeviceAssignment.player_for_event(_stick(1, JOY_AXIS_LEFT_X, 1.0)), 1, "P2 keeps pad 1")
	assert_eq(DeviceAssignment.player_for_event(_stick(0, JOY_AXIS_LEFT_X, 1.0)), -1, "pad 0 gone")
	_restore()

func test_reassign_two_pads_at_once_from_keyboard() -> void:
	var b := DeviceAssignment.reassign(DeviceAssignment.assign(_pads([]), true), _pads([1, 0]), true)
	assert_eq(_kinds(b), [[PAD, 0], [PAD, 1]], "same as assign: pad 0 P1, pad 1 P2")
