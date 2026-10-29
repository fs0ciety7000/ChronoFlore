class_name Hud
extends Control
## Night HUD: one shared clock-flower, the active tool cartouche of each player (P1 bottom left;
## P2 bottom right, co-op only) and capture toasts. Event driven: it listens to the session's
## signals and never polls in _process.

const TOAST_SECONDS := 2.2
const TOAST_FADE := 0.4

@onready var flower: ClockFlower = $TopLeft/Panel/Flower
@onready var tool_panel: PanelContainer = $ToolPanel
@onready var tool_label: Label = $ToolPanel/ToolLabel
@onready var tool_panel_2: PanelContainer = $ToolPanel2
@onready var tool_label_2: Label = $ToolPanel2/ToolLabel2
@onready var toast_panel: PanelContainer = $ToastPanel
@onready var toast_label: Label = $ToastPanel/ToastLabel

var _clock: NightClock
var _lucidity: Lucidity
var _toast_tween: Tween

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
	belt.tool_changed.connect(set_tool)
	session.capture_registered.connect(show_capture)
	set_tool(belt.current())
	tool_panel_2.visible = session.players.size() > 1
	if tool_panel_2.visible:
		var belt_2 := session.players[1].get_node("ToolBelt") as ToolBelt
		belt_2.tool_changed.connect(set_tool_2)
		set_tool_2(belt_2.current())
	_refresh_flower()

func set_tool(tool: ToolData) -> void:
	tool_label.text = tool.display_name if tool != null else "—"

## P2's cartouche (co-op).
func set_tool_2(tool: ToolData) -> void:
	tool_label_2.text = tool.display_name if tool != null else "—"

## Toast "+20 min · Rêvette", plus "Nouvelle page !" on a discovery.
func show_capture(species: PlantSpecies, new_page: bool) -> void:
	var text := "+%d min · %s" % [species.minutes_reward(), species.display_name]
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
		flower.set_state(0.0, 5, 5)
		return
	flower.set_state(_clock.progress(), _lucidity.petals, _lucidity.max_petals)
