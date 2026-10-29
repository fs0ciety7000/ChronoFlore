class_name WakeScreen
extends Control
## Night summary, read from GameState.last_night. Only the heroine dreams: the texts speak of
## her whoever was played.

const TITLE_SCENE := "res://scenes/main.tscn"

@onready var title_label: Label = $Center/Panel/Box/TitleLabel
@onready var summary_label: Label = $Center/Panel/Box/SummaryLabel
@onready var memory_label: Label = $Center/Panel/Box/MemoryLabel
@onready var record_label: Label = $Center/Panel/Box/RecordLabel
@onready var next_button: Button = $Center/Panel/Box/Buttons/NextButton
@onready var title_button: Button = $Center/Panel/Box/Buttons/TitleButton

func _ready() -> void:
	var night := GameState.last_night
	var minutes := int(night.get("minutes", 0))
	if bool(night.get("full", false)):
		title_label.text = "Nuit complète — l'aube !"
	else:
		title_label.text = "Elle se réveille en sursaut à %s" % ClockFlower.format_time(minutes)
	summary_label.text = _summary(night)
	memory_label.text = _memory(night)
	memory_label.visible = not memory_label.text.is_empty()
	record_label.text = "Record : %s" % ClockFlower.format_time(int(night.get("best_minutes", minutes)))
	next_button.pressed.connect(GameState.start_night)
	title_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(TITLE_SCENE))
	next_button.grab_focus()

func _summary(night: Dictionary) -> String:
	var lines: PackedStringArray = []
	var captures: Array = night.get("captures", [])
	if captures.is_empty():
		lines.append("Aucune capture cette nuit.")
	else:
		var tally := {}
		for id: StringName in captures:
			tally[id] = int(tally.get(id, 0)) + 1
		var parts: PackedStringArray = []
		for id: StringName in tally:
			parts.append("%s ×%d" % [_species_name(id), tally[id]])
		lines.append("Captures : %d (%s)" % [captures.size(), ", ".join(parts)])
	for id: StringName in night.get("new_species", []):
		lines.append("Nouvelle page : %s" % _species_name(id))
	for id: StringName in night.get("unlocked", []):
		var tool := GameState.catalog.tool_by_id(id)
		lines.append("Nouvel outil : %s" % (tool.display_name if tool != null else String(id)))
	return "\n".join(lines)

func _memory(night: Dictionary) -> String:
	var index := int(night.get("dawn_memory", -1))
	var memories := GameState.catalog.dawn_memories
	if index < 0 or index >= memories.size():
		return ""
	return "Souvenir d'aube\n%s" % memories[index]

func _species_name(id: StringName) -> String:
	var species := GameState.catalog.species_by_id(id)
	return species.display_name if species != null else String(id)
