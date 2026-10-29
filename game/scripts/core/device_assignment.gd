class_name DeviceAssignment
extends RefCounted
## Who plays with which device, and the InputMap rebuild that applies it at runtime.
## Solo: keyboard-mouse and any pad. Co-op: 2 pads -> one each; 1 pad -> keyboard-mouse for P1,
## the pad for P2; no pad -> shared keyboard (P1 ZQSD/WASD + F + R, P2 arrows + Enter/keypad 0 +
## Period/keypad period, never a modifier: Ctrl+W would close the browser tab), both aiming AUTO. A pad unplugged mid-night sends its player to their keyboard
## half (AUTO aim); the other player keeps their device.
## The project's p1_* / p2_* bindings are the templates: p1 holds the keyboard-mouse keys and the
## pad layout, p2 holds the right-hand keys.

enum Kind { KEYBOARD_MOUSE, KEYBOARD_LEFT, KEYBOARD_RIGHT, PAD }

## "device" of a player who listens to every pad (solo; Godot's all-devices id).
const ALL_PADS := -1
## "device" of a player who listens to no pad.
const NO_PAD := -2
## Per-player action bases (p1_<base>, p2_<base>). `pause` stays shared and is never rebuilt.
const BASES: Array[String] = ["move_left", "move_right", "move_up", "move_down", "aim_left", "aim_right",
		"aim_up", "aim_down", "use_tool", "next_tool", "prev_tool", "tool_1", "tool_2", "tool_3"]

## One {"kind": Kind, "device": int} per player, by the rules above. Pads go lowest id first.
static func assign(pad_ids: Array[int], coop: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not coop:
		out.append(_entry(Kind.KEYBOARD_MOUSE, ALL_PADS))
		return out
	var pads := _sorted(pad_ids)
	match pads.size():
		0:
			out.append(_entry(Kind.KEYBOARD_LEFT, NO_PAD))
			out.append(_entry(Kind.KEYBOARD_RIGHT, NO_PAD))
		1:
			out.append(_entry(Kind.KEYBOARD_MOUSE, NO_PAD))
			out.append(_entry(Kind.PAD, pads[0]))
		_:
			out.append(_entry(Kind.PAD, pads[0]))
			out.append(_entry(Kind.PAD, pads[1]))
	return out

## The assignment after a pad (un)plug: players keep their still-connected pad; a player whose
## pad vanished falls back on their keyboard half (P1 left, P2 right); free pads go to players
## without one (lowest id to P1 when both need one; a single free pad to P2 first). Without a usable previous assignment (or in solo) this is assign().
static func reassign(current: Array[Dictionary], pad_ids: Array[int], coop: bool) -> Array[Dictionary]:
	if not coop or current.size() != 2:
		return assign(pad_ids, coop)
	var pads := _sorted(pad_ids)
	var result: Array[Dictionary] = []
	var had_pad: Array[bool] = []
	for i in 2:
		var entry := current[i]
		var is_pad := int(entry["kind"]) == Kind.PAD
		had_pad.append(is_pad)
		if is_pad and not pads.has(int(entry["device"])):
			result.append(_entry(_half(i), NO_PAD))
		else:
			result.append(_entry(int(entry["kind"]), int(entry["device"])))
	var free: Array[int] = []
	for id in pads:
		if not (result[0]["device"] == id and int(result[0]["kind"]) == Kind.PAD) \
				and not (result[1]["device"] == id and int(result[1]["kind"]) == Kind.PAD):
			free.append(id)
	# Both without a pad and two free: in order (P1 the lowest id); a single free pad goes to P2.
	var order := [0, 1] if free.size() >= 2 else [1, 0]
	for i in order:
		if not free.is_empty() and int(result[i]["kind"]) != Kind.PAD:
			result[i] = _entry(Kind.PAD, free.pop_front())
	var on_keys: Array[int] = []
	for i in 2:
		if int(result[i]["kind"]) != Kind.PAD:
			on_keys.append(i)
	if on_keys.size() == 2:
		result[0] = _entry(Kind.KEYBOARD_LEFT, NO_PAD)
		result[1] = _entry(Kind.KEYBOARD_RIGHT, NO_PAD)
	elif on_keys.size() == 1:
		var other := 1 - on_keys[0]
		if not had_pad[other]: # the other player just took a pad: the keyboard is whole again
			result[on_keys[0]] = _entry(Kind.KEYBOARD_MOUSE, NO_PAD)
	return result

## Keyboard halves have no stick nor mouse: their aim is AUTO.
static func auto_aim(kind: Kind) -> bool:
	return kind == Kind.KEYBOARD_LEFT or kind == Kind.KEYBOARD_RIGHT

## Only the keyboard-mouse player aims with the mouse.
static func uses_mouse(kind: Kind) -> bool:
	return kind == Kind.KEYBOARD_MOUSE

## Rebuilds every p<i>_* action for the assignment, from the project's bindings. Players beyond
## the assignment (P2 in solo) keep the project's bindings.
static func apply(assignments: Array[Dictionary]) -> void:
	InputMap.load_from_project_settings()
	for i in assignments.size():
		var kind: Kind = int(assignments[i]["kind"]) as Kind
		var device := int(assignments[i]["device"])
		for base in BASES:
			var action := StringName("p%d_%s" % [i + 1, base])
			if not InputMap.has_action(action):
				continue
			InputMap.action_erase_events(action)
			for e in events_for(base, kind, device):
				InputMap.action_add_event(action, e)

## Project bindings back (solo defaults): call when the night ends.
static func restore() -> void:
	InputMap.load_from_project_settings()

## Fresh events for one action base and one player's device.
static func events_for(base: String, kind: Kind, device: int) -> Array[InputEvent]:
	var left := _template("p1_" + base)
	var right := _template("p2_" + base)
	var out: Array[InputEvent] = []
	match kind:
		Kind.KEYBOARD_MOUSE:
			for e in left:
				if e is InputEventKey or e is InputEventMouseButton:
					out.append(e)
			if device != NO_PAD:
				out.append_array(_pad_events(left, device))
		Kind.KEYBOARD_LEFT:
			var right_keys: Array[int] = []
			for e in right:
				if e is InputEventKey:
					right_keys.append((e as InputEventKey).physical_keycode)
			for e in left:
				if e is InputEventKey and not right_keys.has((e as InputEventKey).physical_keycode):
					out.append(e)
		Kind.KEYBOARD_RIGHT:
			for e in right:
				if e is InputEventKey:
					out.append(e)
		Kind.PAD:
			if device != NO_PAD:
				out.append_array(_pad_events(left, device))
	return out

## 0 or 1 for the player whose actions match the event, -1 when nobody's do.
static func player_for_event(event: InputEvent) -> int:
	for i in 2:
		for base in BASES:
			var action := StringName("p%d_%s" % [i + 1, base])
			if InputMap.has_action(action) and InputMap.event_is_action(event, action):
				return i
	return -1

static func _pad_events(events: Array[InputEvent], device: int) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	for e in events:
		if e is InputEventJoypadMotion or e is InputEventJoypadButton:
			e.device = device
			out.append(e)
	return out

## Copies of the project's events for an action (never the live InputMap's).
static func _template(action: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	var setting: Variant = ProjectSettings.get_setting("input/" + action)
	if setting is Dictionary and (setting as Dictionary).has("events"):
		for e in (setting as Dictionary)["events"]:
			if e is InputEvent:
				out.append((e as InputEvent).duplicate() as InputEvent)
	return out

static func _half(player: int) -> Kind:
	return Kind.KEYBOARD_LEFT if player == 0 else Kind.KEYBOARD_RIGHT

static func _entry(kind: int, device: int) -> Dictionary:
	return {"kind": kind, "device": device}

static func _sorted(ids: Array[int]) -> Array[int]:
	var out: Array[int] = ids.duplicate()
	out.sort()
	return out
