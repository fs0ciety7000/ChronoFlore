class_name TitleScreen
extends Control

const HERBARIUM_SCENE := "res://scenes/ui/herbarium.tscn"
const SELECT_SCENE := "res://scenes/ui/character_select.tscn"

@onready var start_button: Button = $Center/Box/StartButton
@onready var herbarium_button: Button = $Center/Box/HerbariumButton
@onready var quit_button: Button = $Center/Box/QuitButton
@onready var flower: ClockFlower = $Center/Box/Flower

func _ready() -> void:
	quit_button.visible = not OS.has_feature("web")
	flower.show_label = false
	flower.custom_minimum_size.y = 150.0
	flower.set_state(0.12, 5, 5)
	start_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(SELECT_SCENE))
	herbarium_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(HERBARIUM_SCENE))
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	start_button.grab_focus()
