class_name HerbariumScreen
extends Control
## Herbarium: scrolling list of the 12 species (unknown ones shown as a dark silhouette and
## "???"), one page per species and the dawn memories already read. Opened from the title
## (standalone) or the pause menu (embedded).
## Keyboard / gamepad: up/down moves in the list, right goes to the page, where up/down (and
## the right stick, page up/down anywhere) scroll it, left goes back to the list.

signal closed

const TITLE_SCENE := "res://scenes/main.tscn"
const UNKNOWN := "???"

const THUMB_DIR := "res://assets/custom/plants/thumbs"
const LIST_ICON_SIZE := 52
const LIST_ROW_HEIGHT := 72
## Page scroll: fraction of the visible height per page up/down, pixels per up/down press,
## and pixels per second at full right-stick deflection.
const PAGE_FRACTION := 0.85
const LINE_STEP := 90.0
const STICK_SPEED := 900.0
const STICK_DEADZONE := 0.25
const FOCUS_BORDER := Color("#c9b3f0")

## True when opened over another screen: closing frees the page instead of changing scene.
var embedded: bool = false
var list_buttons: Array[Button] = []

@onready var list_scroll: ScrollContainer = $Panel/Margin/Root/Left/ListScroll
@onready var list_box: VBoxContainer = $Panel/Margin/Root/Left/ListScroll/List
@onready var page_scroll: ScrollContainer = $Panel/Margin/Root/Right/Scroll
@onready var page_box: VBoxContainer = $Panel/Margin/Root/Right/Scroll/Page
@onready var memories_button: Button = $Panel/Margin/Root/Left/MemoriesButton
@onready var back_button: Button = $Panel/Margin/Root/Left/BackButton
@onready var icon: TextureRect = $Panel/Margin/Root/Right/Scroll/Page/Icon
@onready var name_label: Label = $Panel/Margin/Root/Right/Scroll/Page/NameLabel
@onready var emotion_label: Label = $Panel/Margin/Root/Right/Scroll/Page/EmotionLabel
@onready var count_label: Label = $Panel/Margin/Root/Right/Scroll/Page/CountLabel
@onready var fragment_label: Label = $Panel/Margin/Root/Right/Scroll/Page/FragmentLabel
@onready var details_label: Label = $Panel/Margin/Root/Right/Scroll/Page/DetailsLabel
@onready var memories_label: Label = $Panel/Margin/Root/Right/Scroll/Page/MemoriesLabel

var _current: StringName = &""

func _ready() -> void:
	back_button.pressed.connect(close)
	memories_button.pressed.connect(show_memories)
	memories_button.focus_entered.connect(show_memories)
	memories_button.focus_neighbor_right = memories_button.get_path_to(page_scroll)
	var focus_box := StyleBoxFlat.new()
	focus_box.bg_color = Color(0, 0, 0, 0)
	focus_box.set_border_width_all(3)
	focus_box.border_color = FOCUS_BORDER
	focus_box.set_corner_radius_all(14)
	page_scroll.add_theme_stylebox_override("focus", focus_box)
	page_scroll.gui_input.connect(_on_page_gui_input)
	list_scroll.follow_focus = true
	refresh()
	var first := GameState.catalog.species[0].id if not GameState.catalog.species.is_empty() else &""
	show_species(first)
	if not list_buttons.is_empty():
		list_buttons[0].grab_focus()
	else:
		back_button.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (embedded and event.is_action_pressed("pause")):
		close()
		get_viewport().set_input_as_handled()
	elif _scroll_from_event(event, page_scroll.has_focus()):
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	# Right stick scrolls the page from anywhere (the left stick navigates).
	var axis := 0.0
	for device in Input.get_connected_joypads():
		var v := Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)
		if absf(v) > absf(axis):
			axis = v
	if absf(axis) > STICK_DEADZONE:
		scroll_page_by(axis * STICK_SPEED * delta)

## Scrolls the page by pixels (negative = up), clamped to its extent.
func scroll_page_by(pixels: float) -> void:
	var bar := page_scroll.get_v_scroll_bar()
	var top := maxf(bar.max_value - bar.page, 0.0)
	page_scroll.scroll_vertical = int(clampf(page_scroll.scroll_vertical + pixels, 0.0, top))

func _on_page_gui_input(event: InputEvent) -> void:
	if _scroll_from_event(event, true):
		page_scroll.accept_event()

## Page up/down always scroll; up/down only when the page itself has the focus
## (in the list they move between species).
func _scroll_from_event(event: InputEvent, page_focused: bool) -> bool:
	if not (event is InputEventAction or event is InputEventKey or event is InputEventJoypadButton):
		return false
	var page := page_scroll.size.y * PAGE_FRACTION
	if event.is_action_pressed("ui_page_down", true):
		scroll_page_by(page)
	elif event.is_action_pressed("ui_page_up", true):
		scroll_page_by(-page)
	elif page_focused and event.is_action_pressed("ui_down", true):
		scroll_page_by(LINE_STEP)
	elif page_focused and event.is_action_pressed("ui_up", true):
		scroll_page_by(-LINE_STEP)
	else:
		return false
	return true

func close() -> void:
	if embedded:
		closed.emit()
		queue_free()
	else:
		get_tree().change_scene_to_file(TITLE_SCENE)

## Rebuilds the species list and memories from the current herbarium.
func refresh() -> void:
	for b in list_buttons:
		b.queue_free()
		list_box.remove_child(b)
	list_buttons.clear()
	for species in GameState.catalog.species:
		var known := GameState.herbarium.is_discovered(species.id)
		var button := Button.new()
		button.text = species.display_name if known else UNKNOWN
		button.icon = load(thumb_path(species.id, known))
		button.expand_icon = true
		button.custom_minimum_size = Vector2(0, LIST_ROW_HEIGHT)
		button.add_theme_constant_override("icon_max_width", LIST_ICON_SIZE)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_entered.connect(show_species.bind(species.id))
		button.pressed.connect(show_species.bind(species.id))
		list_box.add_child(button)
		button.focus_neighbor_right = button.get_path_to(page_scroll)
		list_buttons.append(button)
	memories_label.text = _memories_text()
	if _current != &"" and not memories_label.visible:
		show_species(_current)

## Thumbnail of a species (rendered once by assets/custom/plants/render_thumbs.gd):
## the model when known, a flat silhouette otherwise.
static func thumb_path(id: StringName, known: bool) -> String:
	return "%s/%s%s.png" % [THUMB_DIR, id, "" if known else "_sil"]

## Fills the page for a species id; unknown species stay hidden.
func show_species(id: StringName) -> void:
	_current = id
	_set_species_page(true)
	var species := GameState.catalog.species_by_id(id)
	if species == null:
		return
	var herbarium := GameState.herbarium
	var known := herbarium.is_discovered(id)
	icon.texture = load(thumb_path(id, known))
	page_scroll.scroll_vertical = 0
	var index := GameState.catalog.species.find(species)
	if index >= 0 and index < list_buttons.size():
		page_scroll.focus_neighbor_left = page_scroll.get_path_to(list_buttons[index])
	if not known:
		name_label.text = UNKNOWN
		emotion_label.text = UNKNOWN
		count_label.text = "Pas encore rencontrée"
		fragment_label.text = ""
		details_label.text = ""
		return
	name_label.text = species.display_name
	emotion_label.text = "Émotion : %s" % species.emotion
	var n := int(herbarium.counts.get(id, 0))
	count_label.text = "Captures : %d" % n
	fragment_label.text = species.fragment
	var lines: PackedStringArray = []
	var revealed := herbarium.revealed_details(id)
	for i in species.details.size():
		if i < revealed:
			lines.append(species.details[i])
		else:
			var needed: int = Herbarium.DETAIL_THRESHOLDS[i]
			lines.append("??? (à %d captures)" % needed)
	details_label.text = "\n\n".join(lines)

## The "Souvenirs d'aube" section: the dawn memories read so far.
func show_memories() -> void:
	_set_species_page(false)
	page_scroll.scroll_vertical = 0
	page_scroll.focus_neighbor_left = page_scroll.get_path_to(memories_button)

func _set_species_page(species_mode: bool) -> void:
	for node: CanvasItem in [icon, name_label, emotion_label, count_label, fragment_label, details_label]:
		node.visible = species_mode
	memories_label.visible = not species_mode

func _memories_text() -> String:
	var lines: PackedStringArray = ["Souvenirs d'aube"]
	var read := mini(GameState.herbarium.next_dawn_memory, GameState.catalog.dawn_memories.size())
	if read == 0:
		lines.append("Aucun souvenir pour l'instant. Ils reviennent à l'aube d'une nuit complète.")
	for i in read:
		lines.append("%d. %s" % [i + 1, GameState.catalog.dawn_memories[i]])
	return "\n\n".join(lines)
