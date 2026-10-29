class_name MuzzlePuff
extends Node3D
## Shot feedback for the dart gun and the harpoon: three soft cream puffs that pop out and fade
## in DURATION seconds at the muzzle, then free themselves.

const DURATION := 0.22
const COLOR := Color(1.0, 0.98, 0.94, 0.95)
const PUFFS := [Vector3(0.0, 0.0, 0.0), Vector3(0.09, 0.05, -0.04), Vector3(-0.08, 0.03, -0.05)]
const RADII := [0.16, 0.11, 0.1]

var _material: StandardMaterial3D

func _ready() -> void:
	_build()

func _build() -> void:
	if _material != null:
		return
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = COLOR
	for i in PUFFS.size():
		var sphere := SphereMesh.new()
		sphere.radius = RADII[i]
		sphere.height = RADII[i] * 2.0
		sphere.radial_segments = 10
		sphere.rings = 5
		var puff := MeshInstance3D.new()
		puff.mesh = sphere
		puff.material_override = _material
		puff.position = PUFFS[i]
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(puff)

func set_opacity(value: float) -> void:
	_build()
	_material.albedo_color.a = COLOR.a * value

## Pops (scale 0.4 -> 1.4) while fading out, then frees itself.
func play() -> void:
	_build()
	scale = Vector3.ONE * 0.4
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "scale", Vector3.ONE * 1.4, DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(set_opacity, 1.0, 0.0, DURATION)
	tween.chain().tween_callback(queue_free)
