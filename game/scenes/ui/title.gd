class_name TitleScreen
extends Control

const HERBARIUM_SCENE := "res://scenes/ui/herbarium.tscn"
const SELECT_SCENE := "res://scenes/ui/character_select.tscn"

@onready var start_button: Button = $Center/Box/StartButton
@onready var herbarium_button: Button = $Center/Box/HerbariumButton
@onready var quit_button: Button = $Center/Box/QuitButton
@onready var flower: ClockFlower = $Center/Box/Flower
## Cream notice shown when the browser keeps no save (private window, blocked storage).
@onready var save_notice: Control = $SaveNotice

func _ready() -> void:
	quit_button.visible = not OS.has_feature("web")
	save_notice.visible = not GameState.persistence_available()
	flower.show_label = false
	flower.custom_minimum_size.y = 150.0
	flower.set_state(0.12, Lucidity.MAX_PETALS, Lucidity.MAX_PETALS)
	start_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(SELECT_SCENE))
	herbarium_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(HERBARIUM_SCENE))
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	start_button.grab_focus()
