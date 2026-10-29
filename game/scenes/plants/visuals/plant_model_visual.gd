class_name PlantModelVisual
extends Node3D
## Hand-made plant model (GLB from assets/custom/plants/build_plants.py) under a "Model" child.
## Plays Idle/Move/Sleep/Caught (+ Attack for hostiles) from the plant state and drives the
## night glow on per-instance material copies, never below the 0.2 light lift every model has.

## Own light lift, same as the heroine's materials.
const LIGHT_LIFT := 0.2
const BLEND := 0.15
const ONE_SHOTS: Array[StringName] = [&"Attack"]

var _anim: AnimationPlayer
var _materials: Array[StandardMaterial3D] = []
var _wanted: StringName = &"Idle"
var _glow: float = 0.0

func _ready() -> void:
	_setup()
	_play(_wanted)

func animation_player() -> AnimationPlayer:
	_setup()
	return _anim

## Per-instance copies of every surface material (glow never leaks between plants).
func materials() -> Array[StandardMaterial3D]:
	_setup()
	return _materials

## WANDER/ALERT/EMERGING -> Idle, FLEE/PANIC/ESCAPED -> Move, asleep -> Sleep, CAPTURED -> Caught.
func play_state(state: Plant.State, asleep: bool) -> void:
	var anim_name: StringName = &"Idle"
	if state == Plant.State.CAPTURED:
		anim_name = &"Caught"
	elif asleep:
		anim_name = &"Sleep"
	elif state == Plant.State.FLEE or state == Plant.State.PANIC or state == Plant.State.ESCAPED:
		anim_name = &"Move"
	_wanted = anim_name
	_setup()
	if _anim == null or not _anim.is_inside_tree():
		return # played in _ready
	if _is_one_shot_playing() and anim_name != &"Caught" and anim_name != &"Sleep":
		return # back to _wanted when the one-shot ends
	_play(anim_name)

## Hostile strike (no-op on models without an Attack animation).
func play_attack() -> void:
	_setup()
	if _anim == null or not _anim.has_animation(&"Attack") or not _anim.is_inside_tree():
		return
	if _anim.current_animation == "Attack":
		_anim.seek(0.0, true)
	else:
		_anim.play(&"Attack", BLEND)

## Night palette plant_glow (0..1); the light lift is the floor of the emission.
func set_glow(value: float) -> void:
	_glow = value
	_setup()
	for mat in _materials:
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = maxf(LIGHT_LIFT, value * Plant.GLOW_ENERGY)

func _setup() -> void:
	if _anim != null:
		return
	var players := find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	_anim = players[0] as AnimationPlayer
	_anim.animation_finished.connect(_on_animation_finished)
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat == null:
				continue
			var copy := mat.duplicate() as StandardMaterial3D
			mi.set_surface_override_material(s, copy)
			_materials.append(copy)
	set_glow(_glow)

func _play(anim_name: StringName) -> void:
	if _anim == null or not _anim.has_animation(anim_name):
		return
	if _anim.current_animation == anim_name and _anim.is_playing():
		return
	_anim.play(anim_name, BLEND)

func _is_one_shot_playing() -> bool:
	return _anim.is_playing() and StringName(_anim.current_animation) in ONE_SHOTS

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name in ONE_SHOTS:
		_play(_wanted)
