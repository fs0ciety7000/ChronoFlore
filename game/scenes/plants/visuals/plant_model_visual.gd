class_name PlantModelVisual
extends Node3D
## Hand-made plant model (GLB from assets/custom/plants/build_plants.py) under a "Model" child.
## Plays Idle/Move/Sleep/Caught (+ Attack for hostiles) from the plant state and drives the
## night glow on per-instance material copies, never below the 0.2 light lift every model has.
## At night the glow is a deeper tint of each colour plus a soft rim, so the pastel models stay
## readable against the lavender night instead of washing out to white.

## Own light lift, same as the heroine's materials.
const LIGHT_LIFT := 0.2
const BLEND := 0.15
const ONE_SHOTS: Array[StringName] = [&"Attack"]
## The Attack clip strikes (lunge, snap, burst) at this fraction of its length (build_plants.py).
const ATTACK_STRIKE_FRACTION := 20.0 / 36.0
const ATTACK_MIN_SPEED := 0.25
const ATTACK_MAX_SPEED := 4.0
## Materials named Glow* (Lumiole's bulb, fireflies) keep their own emission as the floor.
const OWN_GLOW_PREFIX := "Glow"
## Lights carried by a model (Lumiole) shine at this fraction of their energy by day.
const LIGHT_DAY_FACTOR := 0.0
## Night readability: at full glow the emission is a deeper tint of the albedo (saturation
## scaled and lifted, value lowered) instead of a wash towards white...
const NIGHT_SATURATION_SCALE := 2.3
const NIGHT_SATURATION_LIFT := 0.08
const NIGHT_VALUE_SCALE := 0.85
## ...and a soft rim (StandardMaterial3D rim, tinted by the albedo) outlines the model.
const NIGHT_RIM := 1.0
const NIGHT_RIM_TINT := 0.5
## Light sources (Glow*) take only part of that tint: they stay warm white.
const OWN_GLOW_TINT := 0.4

var _anim: AnimationPlayer
var _materials: Array[StandardMaterial3D] = []
var _floors: Array[float] = [] ## emission floor per material (LIGHT_LIFT, or its own for Glow*)
var _lights: Array[Light3D] = []
var _light_energy: Array[float] = []
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
## `approaching`: a hostile moving in WANDER (stalking, charging) plays Move too.
func play_state(state: Plant.State, asleep: bool, approaching: bool = false) -> void:
	var anim_name: StringName = &"Idle"
	if state == Plant.State.CAPTURED:
		anim_name = &"Caught"
	elif asleep:
		anim_name = &"Sleep"
	elif state == Plant.State.FLEE or state == Plant.State.PANIC or state == Plant.State.ESCAPED:
		anim_name = &"Move"
	elif state == Plant.State.WANDER and approaching:
		anim_name = &"Move"
	_wanted = anim_name
	_setup()
	if _anim == null or not _anim.is_inside_tree():
		return # played in _ready
	if _is_one_shot_playing() and anim_name != &"Caught" and anim_name != &"Sleep":
		return # back to _wanted when the one-shot ends
	_play(anim_name)

## Hostile strike (no-op on models without an Attack animation). With impact_in > 0 the clip is
## time-stretched so its strike key (ATTACK_STRIKE_FRACTION of the clip) lands then: the
## wind-up reads as the telegraph.
func play_attack(impact_in: float = 0.0) -> void:
	_setup()
	if _anim == null or not _anim.has_animation(&"Attack") or not _anim.is_inside_tree():
		return
	var speed := 1.0
	if impact_in > 0.0:
		var strike := _anim.get_animation(&"Attack").length * ATTACK_STRIKE_FRACTION
		speed = clampf(strike / impact_in, ATTACK_MIN_SPEED, ATTACK_MAX_SPEED)
	_anim.play(&"Attack", BLEND, speed)
	_anim.seek(0.0, true)

## Night palette plant_glow (0..1); the light lift is the floor of the emission.
func set_glow(value: float) -> void:
	_glow = value
	_setup()
	var night := clampf(value, 0.0, 1.0)
	for i in _materials.size():
		var mat := _materials[i]
		mat.emission_enabled = true
		var tint := night * (OWN_GLOW_TINT if mat.resource_name.begins_with(OWN_GLOW_PREFIX) else 1.0)
		mat.emission = mat.albedo_color.lerp(_night_tint(mat.albedo_color), tint)
		mat.emission_energy_multiplier = maxf(_floors[i], value * Plant.GLOW_ENERGY)
		mat.rim_enabled = night > 0.0
		mat.rim = NIGHT_RIM * night
		mat.rim_tint = NIGHT_RIM_TINT
	for i in _lights.size():
		_lights[i].light_energy = _light_energy[i] * lerpf(LIGHT_DAY_FACTOR, 1.0, night)
		_lights[i].visible = _lights[i].light_energy > 0.001

## Imported emission strength relative to the albedo (glTF folds strengths <= 1 into the
## emissive colour and keeps strengths > 1 in the energy).
static func _own_emission(mat: StandardMaterial3D) -> float:
	if not mat.emission_enabled:
		return 0.0
	var e := mat.emission.srgb_to_linear()
	var a := mat.albedo_color.srgb_to_linear()
	var a_max := maxf(a.r, maxf(a.g, a.b))
	if a_max < 1e-4:
		return mat.emission_energy_multiplier
	return mat.emission_energy_multiplier * maxf(e.r, maxf(e.g, e.b)) / a_max

## Deeper, same-hue version of a pastel albedo.
static func _night_tint(c: Color) -> Color:
	if c.s < 0.02:
		return c # whites and greys stay neutral
	return Color.from_hsv(c.h, minf(c.s * NIGHT_SATURATION_SCALE + NIGHT_SATURATION_LIFT, 1.0),
		c.v * NIGHT_VALUE_SCALE, c.a)

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
			var own := _own_emission(mat)
			_floors.append(maxf(LIGHT_LIFT, own) if mat.resource_name.begins_with(OWN_GLOW_PREFIX) else LIGHT_LIFT)
	for node in find_children("*", "Light3D", true, false):
		_lights.append(node as Light3D)
		_light_energy.append((node as Light3D).light_energy)
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
