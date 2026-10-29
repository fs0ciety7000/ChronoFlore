class_name HerbariumScreen
extends Control
## Herbarium: list of species (unknown ones hidden as "???"), one page per species and the
## dawn memories already read. Opened from the title (standalone) or the pause menu (embedded).

signal closed

const TITLE_SCENE := "res://scenes/main.tscn"
const UNKNOWN := "???"
const RARITY_TINT := {
	PlantSpecies.Rarity.COMMON: Color("#f3a6c0"),
	PlantSpecies.Rarity.UNCOMMON: Color("#c9b3f0"),
	PlantSpecies.Rarity.RARE: Color("#f6c177"),
}

## True when opened over another screen: closing frees the page instead of changing scene.
var embedded: bool = false
var list_buttons: Array[Button] = []

@onready var list_box: VBoxContainer = $Panel/Margin/Root/Left/List
@onready var memories_button: Button = $Panel/Margin/Root/Left/MemoriesButton
@onready var back_button: Button = $Panel/Margin/Root/Left/BackButton
@onready var icon: PlantIcon = $Panel/Margin/Root/Right/Scroll/Page/Icon
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
	refresh()
	var first := GameState.catalog.species[0].id if not GameState.catalog.species.is_empty() else &""
	show_species(first)
	if not list_buttons.is_empty():
		list_buttons[0].grab_focus()
	else:
		back_button.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

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
		var button := Button.new()
		button.text = species.display_name if GameState.herbarium.is_discovered(species.id) else UNKNOWN
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_entered.connect(show_species.bind(species.id))
		button.pressed.connect(show_species.bind(species.id))
		list_box.add_child(button)
		list_buttons.append(button)
	memories_label.text = _memories_text()
	if _current != &"" and not memories_label.visible:
		show_species(_current)

## Fills the page for a species id; unknown species stay hidden.
func show_species(id: StringName) -> void:
	_current = id
	_set_species_page(true)
	var species := GameState.catalog.species_by_id(id)
	if species == null:
		return
	var herbarium := GameState.herbarium
	var known := herbarium.is_discovered(id)
	icon.set_species(known, RARITY_TINT[species.rarity])
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
	count_label.text = ("Captures : %d" if species.capturable else "Endormie : %d fois") % n
	fragment_label.text = species.fragment
	var lines: PackedStringArray = []
	var revealed := herbarium.revealed_details(id)
	for i in species.details.size():
		if i < revealed:
			lines.append(species.details[i])
		else:
			var needed: int = Herbarium.DETAIL_THRESHOLDS[i]
			lines.append("??? (à %d %s)" % [needed, "captures" if species.capturable else "sommeils"])
	details_label.text = "\n\n".join(lines)

## The "Souvenirs d'aube" section: the dawn memories read so far.
func show_memories() -> void:
	_set_species_page(false)

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
