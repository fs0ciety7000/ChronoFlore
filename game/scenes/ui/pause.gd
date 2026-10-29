class_name PauseMenu
extends Control
## Pause overlay. Runs while the tree is paused (process_mode ALWAYS in the scene).

signal resumed
signal abandoned

const HERBARIUM_SCENE := preload("res://scenes/ui/herbarium.tscn")

@onready var panel: Control = $Center
@onready var resume_button: Button = $Center/Panel/Box/ResumeButton
@onready var herbarium_button: Button = $Center/Panel/Box/HerbariumButton
@onready var abandon_button: Button = $Center/Panel/Box/AbandonButton

func _ready() -> void:
	resume_button.pressed.connect(resume)
	herbarium_button.pressed.connect(_open_herbarium)
	abandon_button.pressed.connect(abandon)
	resume_button.grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible:
		return # the herbarium on top handles its own cancel
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		resume()
		get_viewport().set_input_as_handled()

func resume() -> void:
	get_tree().paused = false
	resumed.emit()
	queue_free()

## Ends the night at the current time.
func abandon() -> void:
	get_tree().paused = false
	abandoned.emit()
	queue_free()

func _open_herbarium() -> void:
	var page := HERBARIUM_SCENE.instantiate() as HerbariumScreen
	page.embedded = true
	panel.hide()
	page.closed.connect(func() -> void:
		panel.show()
		resume_button.grab_focus())
	add_child(page)
