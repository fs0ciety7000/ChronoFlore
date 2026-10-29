class_name NightLighting
extends Node3D
## Drives the sun, ambient light and background from night progress via NightPalette.
## The displayed progress eases towards target_progress so captures never cause a jump.

signal glow_changed(value: float)

const EASE_RATE: float = 1.5
const GLOW_EPSILON: float = 0.01
## Fixed sun heading; only the pitch follows the palette.
const SUN_YAW_DEG: float = -30.0
## Camera-to-scene distance the palette tint is calibrated for (IsoCamera.DISTANCE).
const TINT_REFERENCE_DISTANCE: float = 40.0

## Night progress to reach (0 = 0 h, 1 = 8 h).
@export var target_progress: float = 0.0

var _display_progress: float = 0.0
var _last_glow: float = 0.0
var _last_glow_ready: bool = false

func _ready() -> void:
	_apply()

func _process(delta: float) -> void:
	_display_progress = lerpf(_display_progress, target_progress, 1.0 - exp(-EASE_RATE * delta))
	_apply()

## Sets the displayed progress immediately (tests, scene start).
func set_display_progress(progress: float) -> void:
	_display_progress = clampf(progress, 0.0, 1.0)
	_apply()

func get_display_progress() -> float:
	return _display_progress

# Children are looked up on each call (not @onready) so this also works before _ready.
func _apply() -> void:
	var p: Dictionary = NightPalette.sample(_display_progress)
	var env: Environment = ($WorldEnvironment as WorldEnvironment).environment
	var sun := $Sun as DirectionalLight3D
	env.background_color = p["background"]
	env.ambient_light_color = p["ambient_color"]
	env.ambient_light_energy = p["ambient_energy"]
	env.adjustment_saturation = p["saturation"]
	# Uniform fog (the ortho camera sees everything at ~the same depth) tints the whole diorama.
	var tint: float = clampf(float(p["tint"]), 0.0, 0.95)
	env.fog_enabled = tint > 0.001
	env.fog_light_color = p["ambient_color"]
	env.fog_density = -log(1.0 - tint) / TINT_REFERENCE_DISTANCE
	sun.light_color = p["sun_color"]
	sun.light_energy = p["sun_energy"]
	sun.rotation_degrees = Vector3(float(p["sun_pitch_deg"]), SUN_YAW_DEG, 0.0)
	var glow: float = p["plant_glow"]
	if not _last_glow_ready:
		_last_glow_ready = true # first application sets the baseline without emitting
		_last_glow = glow
	elif absf(glow - _last_glow) > GLOW_EPSILON:
		_last_glow = glow
		glow_changed.emit(glow)
