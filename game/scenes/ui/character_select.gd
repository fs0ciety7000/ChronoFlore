class_name CharacterSelect
extends Control
## Who plays the night: « Elle » (the heroine), « Lui » (the hero, a figure of her dream) or
## « À deux » (local co-op). Opens with the current GameState.mode focused, so the shown choice
## is the kept one. Keyboard and gamepad navigate with the ui_* actions.

## A card was picked (GameState.mode is already set).
signal chosen(mode: GameState.Mode)

const TITLE_SCENE := "res://scenes/main.tscn"
## The focused card is also filled blush pink, so the choice reads at a glance.
const FOCUS_FILL := Color(1.0, 0.91, 0.94, 1.0)

## Tests set this to false to stay on this screen.
@export var auto_change_scene := true

## Indexed by GameState.Mode.
var cards: Array[Button] = []

@onready var heroine_card: Button = $Center/Box/Cards/HeroineCard
@onready var hero_card: Button = $Center/Box/Cards/HeroCard
@onready var coop_card: Button = $Center/Box/Cards/CoopCard
@onready var back_button: Button = $Center/Box/BackButton

func _ready() -> void:
	cards = [heroine_card, hero_card, coop_card]
	var focus := (get_theme_stylebox(&"focus", &"Button") as StyleBoxFlat).duplicate() as StyleBoxFlat
	focus.draw_center = true
	focus.bg_color = FOCUS_FILL
	for i in cards.size():
		var card := cards[i]
		card.pressed.connect(choose.bind(i as GameState.Mode))
		card.add_theme_stylebox_override(&"focus", focus)
		card.focus_neighbor_left = card.get_path_to(cards[i - 1] if i > 0 else card)
		card.focus_neighbor_right = card.get_path_to(cards[i + 1] if i < cards.size() - 1 else card)
		card.focus_neighbor_bottom = card.get_path_to(back_button)
		card.focus_entered.connect(func() -> void:
			back_button.focus_neighbor_top = back_button.get_path_to(card))
	back_button.pressed.connect(go_back)
	cards[GameState.mode].grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		go_back()

func choose(mode: GameState.Mode) -> void:
	GameState.mode = mode
	chosen.emit(mode)
	if auto_change_scene:
		GameState.start_night_with(mode)

## Back to the title; the mode is left as it was.
func go_back() -> void:
	if auto_change_scene:
		get_tree().change_scene_to_file(TITLE_SCENE)
