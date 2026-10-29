class_name Hud
extends Control
## Night HUD: one shared clock-flower, P1's tool cartouche with the tool bar (Filet [1],
## Fusil [2], Harpon [3], locked tools padlocked), P2's cartouche (bottom right, co-op only),
## capture toasts and a one-time "change tool" hint. Event driven: it listens to the session's
## signals and never polls in _process; key hints follow the last device used.

const TOAST_SECONDS := 2.2
const TOAST_FADE := 0.4
const HINT_SECONDS := 7.0
const HINT_KEYBOARD := "Molette / 1-2-3 : changer d'outil"
const HINT_PAD := "LB / RB : changer d'outil"
## A stick must move this far to count as "using the pad" (drift is ignored).
const PAD_AXIS_THRESHOLD := 0.5

@onready var flower: ClockFlower = $TopLeft/Panel/Flower
@onready var tool_panel: PanelContainer = $ToolPanel
@onready var tool_label: Label = $ToolPanel/Box/ToolLabel
@onready var tool_bar: ToolBar = $ToolPanel/Box/ToolBar
@onready var tool_hint: PanelContainer = $ToolHint
@onready var hint_label: Label = $ToolHint/HintLabel
@onready var tool_panel_2: PanelContainer = $ToolPanel2
@onready var tool_label_2: Label = $ToolPanel2/ToolLabel2
@onready var toast_panel: PanelContainer = $ToastPanel
@onready var toast_label: Label = $ToastPanel/ToastLabel

var _clock: NightClock
var _lucidity: Lucidity
var _toast_tween: Tween
var _hint_tween: Tween
var pad_mode: bool = false

func _ready() -> void:
	toast_panel.modulate.a = 0.0
	tool_label.text = "—"
	_refresh_flower()

## Connects to a running session (clock, lucidity, P1's tool belt, P2's in co-op, captures).
func bind(session: NightSession, belt: ToolBelt) -> void:
	_clock = session.clock
	_lucidity = session.lucidity
	_clock.minutes_changed.connect(func(_m: int) -> void: _refresh_flower())
	_lucidity.petal_lost.connect(func(_p: int) -> void: _refresh_flower())
	_lucidity.petal_regrown.connect(func(_p: int) -> void: _refresh_flower())
	tool_bar.setup(GameState.catalog, belt.tools)
	belt.tool_changed.connect(set_tool)
	session.capture_registered.connect(show_capture)
	set_tool(belt.current())
	if belt.tools.size() > 1 and not GameState.tool_hint_shown:
		GameState.tool_hint_shown = true
		show_tool_hint()
		var first := belt.current()
		belt.tool_changed.connect(func(t: ToolData) -> void:
			if t != first:
				hide_tool_hint())
	tool_panel_2.visible = session.players.size() > 1
	if tool_panel_2.visible:
		var belt_2 := session.players[1].get_node("ToolBelt") as ToolBelt
		belt_2.tool_changed.connect(set_tool_2)
		set_tool_2(belt_2.current())
	_refresh_flower()

func set_tool(tool: ToolData) -> void:
	tool_label.text = tool.display_name if tool != null else "—"
	if tool_bar != null:
		tool_bar.select(tool)

## The key of a locked tool was pressed: shake its slot.
func nudge_locked(index: int) -> void:
	tool_bar.nudge(index)

## One-time hint above the tool bar; fades after HINT_SECONDS or on the first tool change.
func show_tool_hint() -> void:
	hint_label.text = HINT_PAD if pad_mode else HINT_KEYBOARD
	tool_hint.visible = true
	tool_hint.modulate.a = 1.0
	if _hint_tween != null:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(HINT_SECONDS)
	_hint_tween.tween_property(tool_hint, "modulate:a", 0.0, TOAST_FADE)
	_hint_tween.tween_callback(func() -> void: tool_hint.visible = false)

func hide_tool_hint() -> void:
	if not tool_hint.visible:
		return
	if _hint_tween != null:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_property(tool_hint, "modulate:a", 0.0, TOAST_FADE)
	_hint_tween.tween_callback(func() -> void: tool_hint.visible = false)

## Key hints follow the last device: pad buttons / sticks, or keyboard and mouse.
func set_pad_mode(on: bool) -> void:
	pad_mode = on
	tool_bar.set_pad_mode(on)
	if tool_hint.visible:
		hint_label.text = HINT_PAD if on else HINT_KEYBOARD

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.is_pressed():
		if not pad_mode:
			set_pad_mode(true)
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > PAD_AXIS_THRESHOLD:
		if not pad_mode:
			set_pad_mode(true)
	elif event is InputEventKey or event is InputEventMouseButton:
		if pad_mode:
			set_pad_mode(false)

## P2's cartouche (co-op).
func set_tool_2(tool: ToolData) -> void:
	tool_label_2.text = tool.display_name if tool != null else "—"

## Toast "+20 min · Rêvette", plus "Nouvelle page !" on a discovery.
func show_capture(species: PlantSpecies, new_page: bool) -> void:
	var text := "+%d min · %s" % [GameState.capture_minutes(species), species.display_name]
	if new_page:
		text += "\nNouvelle page !"
	toast_label.text = text
	if _toast_tween != null:
		_toast_tween.kill()
	toast_panel.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_SECONDS)
	_toast_tween.tween_property(toast_panel, "modulate:a", 0.0, TOAST_FADE)

func _refresh_flower() -> void:
	if flower == null:
		return
	if _clock == null or _lucidity == null:
		flower.set_state(0.0, Lucidity.MAX_PETALS, Lucidity.MAX_PETALS)
		return
	flower.set_state(_clock.progress(), _lucidity.petals, _lucidity.max_petals)
