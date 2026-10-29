class_name ToolBar
extends HBoxContainer
## P1's tool bar: one slot per catalog tool (Filet [1], Fusil [2], Harpon [3]). The selected
## slot is filled blush pink; a locked tool shows a padlock and the species count that unlocks
## it. Key hints follow the active device: the 1/2/3 keys, or the pad bumpers (LB / RB).

const SHORT_NAMES := {&"net": "Filet", &"tranquilizer": "Fusil", &"harpoon": "Harpon"}
const INK := Color(0.29, 0.247, 0.361, 1.0)
const MUTED := Color(0.29, 0.247, 0.361, 0.45)
const FILL := Color(0.992, 0.965, 0.918, 1.0)
const SELECTED_FILL := Color(1.0, 0.86, 0.91, 1.0)
const SELECTED_BORDER := Color(0.953, 0.5, 0.66, 1.0)
const BORDER := Color(0.788, 0.702, 0.941, 1.0)
const NUDGE_TIME := 0.3

## One Dictionary per slot: {id, panel, name, hint, lock, locked}.
var slots: Array[Dictionary] = []
var pad_mode: bool = false

var _catalog: GameCatalog
var _selected: StringName = &""

## Builds the slots for every catalog tool; `available` are the belt's tools (others are locked).
func setup(catalog: GameCatalog, available: Array[ToolData]) -> void:
	_catalog = catalog
	for c in get_children():
		c.queue_free()
	slots.clear()
	add_theme_constant_override(&"separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in catalog.tools.size():
		var tool := catalog.tools[i]
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.custom_minimum_size = Vector2(92, 0)
		var box := VBoxContainer.new()
		box.add_theme_constant_override(&"separation", 0)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(box)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(row)
		var lock := Padlock.new()
		row.add_child(lock)
		var name_label := _label(SHORT_NAMES.get(tool.id, tool.display_name), 20)
		row.add_child(name_label)
		var hint := _label("", 15)
		box.add_child(hint)
		add_child(panel)
		slots.append({"id": tool.id, "panel": panel, "name": name_label, "hint": hint, "lock": lock, "locked": false})
	set_available(available)

func set_available(available: Array[ToolData]) -> void:
	var ids: Array[StringName] = []
	for t in available:
		ids.append(t.id)
	for i in slots.size():
		slots[i]["locked"] = not ids.has(slots[i]["id"])
	_refresh(_selected)

## Highlights the slot of `tool` (null: none).
func select(tool: ToolData) -> void:
	_refresh(tool.id if tool != null else &"")

func set_pad_mode(on: bool) -> void:
	if on == pad_mode:
		return
	pad_mode = on
	_refresh(_selected)

## Species needed to unlock `id` (0 if no milestone).
func unlock_requirement(id: StringName) -> int:
	if _catalog != null:
		for m in _catalog.milestones:
			if m.reward_tool_id == id:
				return m.capturable_species_required
	return 0

## Short shake of a locked slot (its key was pressed).
func nudge(index: int) -> void:
	if index < 0 or index >= slots.size():
		return
	var panel: Control = slots[index]["panel"]
	var tween := panel.create_tween()
	for k in 3:
		tween.tween_property(panel, "rotation", deg_to_rad(4.0), NUDGE_TIME / 6.0)
		tween.tween_property(panel, "rotation", deg_to_rad(-4.0), NUDGE_TIME / 6.0)
	tween.tween_property(panel, "rotation", 0.0, 0.03)
	panel.pivot_offset = panel.size * 0.5

func slot_hint(index: int) -> String:
	return (slots[index]["hint"] as Label).text

func is_locked(index: int) -> bool:
	return bool(slots[index]["locked"])

func selected_index() -> int:
	for i in slots.size():
		if slots[i]["id"] == _selected:
			return i
	return -1

func _refresh(selected: StringName) -> void:
	_selected = selected
	for i in slots.size():
		var slot := slots[i]
		var locked := bool(slot["locked"])
		var on: bool = slot["id"] == selected and not locked
		var style := StyleBoxFlat.new()
		style.bg_color = SELECTED_FILL if on else FILL
		style.border_color = SELECTED_BORDER if on else BORDER
		style.set_border_width_all(4 if on else 2)
		style.set_corner_radius_all(14)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		if not on:
			style.bg_color.a = 0.85
		(slot["panel"] as PanelContainer).add_theme_stylebox_override(&"panel", style)
		(slot["lock"] as Control).visible = locked
		(slot["name"] as Label).add_theme_color_override(&"font_color", MUTED if locked else INK)
		var hint: Label = slot["hint"]
		if locked:
			hint.text = "%d espèces" % unlock_requirement(slot["id"])
		elif pad_mode:
			hint.text = "LB / RB" if on else ""
		else:
			hint.text = "[%d]" % (i + 1)
		hint.add_theme_color_override(&"font_color", MUTED if locked or not on else INK)

func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Small drawn padlock (no emoji font needed).
class Padlock:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(18, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Color(0.29, 0.247, 0.361, 0.7)
		draw_arc(Vector2(9, 9), 5.0, PI, TAU, 12, c, 2.5, true)
		draw_line(Vector2(4, 9), Vector2(4, 11), c, 2.5)
		draw_line(Vector2(14, 9), Vector2(14, 11), c, 2.5)
		draw_rect(Rect2(2, 11, 14, 10), c)
