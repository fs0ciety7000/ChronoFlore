extends Node3D
## Hand-made character visual (heroine.glb by default, ~1.1 m, faces +Z) holding the current
## tool in hand.R (HandTools: Net, DartGun, Harpoon). Plays Idle/Walk by movement, Swing when a
## tool is used and Hurt + a white blink on hits. Reused by hero2_visual.tscn with another model.

const LOCOMOTION_BLEND := 0.15
const ONE_SHOT_BLEND := 0.05
## The 0.6 s Walk cycle is sped up to keep pace with the 5 m/s arcade movement.
const WALK_SPEED := 1.5
const ONE_SHOTS: Array[StringName] = [&"Swing", &"Hurt"]
const FLASH_ALPHA := 0.85
## Hand prop shown for each tool effect; the net is the default.
const TOOL_PROPS := {
	ToolData.Effect.CAPTURE: ^"Net",
	ToolData.Effect.TORPOR: ^"DartGun",
	ToolData.Effect.PIN: ^"Harpoon",
}

## Skinned body mesh (gets the hurt flash overlay); set per model scene.
@export var body_mesh_path: NodePath = ^"Model/Heroine/Skeleton3D/HeroineMesh"
## Parent of the Net/DartGun/Harpoon props, under the hand.R BoneAttachment3D.
@export var hand_tools_path: NodePath = ^"Model/Heroine/Skeleton3D/HandR/HandTools"

var _walking: bool = false
var _flash: StandardMaterial3D
var _blink: Tween
@onready var _anim: AnimationPlayer = $Model/AnimationPlayer
@onready var _mesh: MeshInstance3D = get_node(body_mesh_path)
@onready var _hand_tools: Node3D = get_node_or_null(hand_tools_path)

func _ready() -> void:
	# Hurt flash: a white unshaded overlay whose alpha is tweened.
	_flash = StandardMaterial3D.new()
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash.albedo_color = Color(1, 1, 1, 0)
	_mesh.material_overlay = _flash
	_anim.animation_finished.connect(_on_animation_finished)
	_anim.play(&"Idle")

func animation_player() -> AnimationPlayer:
	return _anim

func set_walking(on: bool) -> void:
	if on == _walking:
		return
	_walking = on
	if not _is_one_shot_playing():
		_play_locomotion()

## Shows the prop of `tool` in hand (wired to ToolBelt.tool_changed by Heroine); null = net.
func set_tool(tool: ToolData) -> void:
	if _hand_tools == null:
		return
	var shown: NodePath = TOOL_PROPS[tool.effect] if tool != null else ^"Net"
	for prop in _hand_tools.get_children():
		(prop as Node3D).visible = NodePath(prop.name) == shown

## Name of the visible hand prop ("" if none).
func shown_tool_prop() -> String:
	if _hand_tools != null:
		for prop in _hand_tools.get_children():
			if (prop as Node3D).visible:
				return prop.name
	return ""

## Net/tool swing (wired to ToolBelt.tool_used by Heroine).
func play_swing() -> void:
	_play_one_shot(&"Swing")

## Quick flinch and white flash while invulnerable.
func blink_hurt() -> void:
	_play_one_shot(&"Hurt")
	if _blink != null:
		_blink.kill()
	_blink = create_tween().set_loops(3)
	_blink.tween_method(_set_flash, 0.0, 1.0, 0.08)
	_blink.tween_method(_set_flash, 1.0, 0.0, 0.08)

func _play_one_shot(anim_name: StringName) -> void:
	if _anim.current_animation == anim_name:
		_anim.seek(0.0, true) # restart instead of ignoring a repeated trigger
	else:
		_anim.play(anim_name, ONE_SHOT_BLEND)

func _play_locomotion() -> void:
	if _walking:
		_anim.play(&"Walk", LOCOMOTION_BLEND, WALK_SPEED)
	else:
		_anim.play(&"Idle", LOCOMOTION_BLEND)

func _is_one_shot_playing() -> bool:
	return _anim.is_playing() and StringName(_anim.current_animation) in ONE_SHOTS

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name in ONE_SHOTS:
		_play_locomotion()

func _set_flash(v: float) -> void:
	_flash.albedo_color.a = v * FLASH_ALPHA
