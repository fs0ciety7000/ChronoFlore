extends Node3D
## Hand-made heroine (assets/custom/heroine/heroine.glb, ~1.1 m, faces +Z) with a net in hand.R.
## Plays Idle/Walk by movement, Swing when a tool is used and Hurt + a white blink on hits.

const LOCOMOTION_BLEND := 0.15
const ONE_SHOT_BLEND := 0.05
## The 0.6 s Walk cycle is sped up to keep pace with the 5 m/s arcade movement.
const WALK_SPEED := 1.5
const ONE_SHOTS: Array[StringName] = [&"Swing", &"Hurt"]
const FLASH_ALPHA := 0.85

var _walking: bool = false
var _flash: StandardMaterial3D
var _blink: Tween
@onready var _anim: AnimationPlayer = $Model/AnimationPlayer
@onready var _mesh: MeshInstance3D = $Model/Heroine/Skeleton3D/HeroineMesh

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
