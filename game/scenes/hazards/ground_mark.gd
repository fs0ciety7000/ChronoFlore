class_name GroundMark
extends MeshInstance3D
## Soft ground sign (telegraph.gdshader) under a hostile attack: a disc of a given radius, or
## a lane from the node's origin along its local +Z. progress (0..1) fills it up to the impact.

enum Shape { DISC, LANE }

const SHADER := preload("res://scenes/hazards/telegraph.gdshader")
## Lifted above the ground to avoid z-fighting with the meadow.
const LIFT := 0.04

var _material: ShaderMaterial

## Disc of `radius` metres centred on the node.
static func disc(radius: float, rim: Color, fill: Color) -> GroundMark:
	var mark := GroundMark.new()
	mark._build(Vector2(radius * 2.0, radius * 2.0), Vector3(0.0, LIFT, 0.0), Shape.DISC, rim, fill)
	return mark

## Lane `length` x `width` metres starting at the node and running along its local +Z.
static func lane(length: float, width: float, rim: Color, fill: Color) -> GroundMark:
	var mark := GroundMark.new()
	mark._build(Vector2(width, length), Vector3(0.0, LIFT, length * 0.5), Shape.LANE, rim, fill)
	return mark

## Resizes a disc mark to `radius` metres.
func resize_disc(radius: float) -> void:
	(mesh as PlaneMesh).size = Vector2(radius * 2.0, radius * 2.0)

func set_progress(value: float) -> void:
	_material.set_shader_parameter("progress", clampf(value, 0.0, 1.0))

func set_opacity(value: float) -> void:
	_material.set_shader_parameter("opacity", clampf(value, 0.0, 1.0))

## Faster pulse as the impact nears.
func set_pulse_rate(value: float) -> void:
	_material.set_shader_parameter("pulse_rate", value)

func material() -> ShaderMaterial:
	return _material

func _build(size: Vector2, offset: Vector3, shape: Shape, rim: Color, fill: Color) -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	plane.center_offset = offset
	mesh = plane
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("rim_color", rim)
	_material.set_shader_parameter("fill_color", fill)
	_material.set_shader_parameter("shape", int(shape))
	_material.set_shader_parameter("progress", 0.0)
	material_override = _material
