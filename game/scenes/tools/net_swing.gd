class_name NetSwing
extends MeshInstance3D
## Net swoosh: a translucent white-to-pink trail sweeping a flat arc of +/- half_angle degrees
## around local +Z, from INNER_RATIO x radius out to radius (the capture cone at net reach).
## play() sweeps it from the right hand side across in DURATION seconds, then frees it.

const SHADER := preload("res://scenes/tools/net_swing.gdshader")
const DURATION := 0.25
const SEGMENTS := 32
const INNER_RATIO := 0.45
## Shader progress at the end: the head has left the arc and the trail has faded out.
const END_PROGRESS := 1.6

@export var half_angle: float = 60.0
@export var radius: float = 2.0

var _material: ShaderMaterial

func _ready() -> void:
	_build()

func _build() -> void:
	if _material != null:
		return
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var inner := radius * INNER_RATIO
	for i in SEGMENTS + 1:
		var u := float(i) / SEGMENTS
		# u = 0 on her right (-X when facing +Z): a forehand sweep of the right-hand net.
		var a := deg_to_rad(lerpf(-half_angle, half_angle, u))
		var d := Vector3(sin(a), 0.0, cos(a))
		verts.append(d * inner)
		uvs.append(Vector2(u, 0.0))
		verts.append(d * radius)
		uvs.append(Vector2(u, 1.0))
		if i > 0:
			var b := (i - 1) * 2
			indices.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = m
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_progress(0.0)

func material() -> ShaderMaterial:
	_build()
	return _material

## Head position along the sweep (0 start .. 1 end; beyond 1 only the fading trail remains).
func set_progress(value: float) -> void:
	material().set_shader_parameter("progress", value)

func set_opacity(value: float) -> void:
	material().set_shader_parameter("opacity", value)

## Sweeps once and frees itself.
func play() -> void:
	_build()
	var tween := create_tween()
	tween.tween_method(set_progress, 0.0, END_PROGRESS, DURATION)
	tween.tween_callback(queue_free)
