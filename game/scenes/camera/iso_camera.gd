class_name IsoCamera
extends Node3D
## Fixed-angle orthographic follow camera. This node sits on the look-at point; the Camera3D
## child is offset along the iso view axis. The focus point is clamped to `bounds` (XZ).

const PITCH_DEG := -35.264
const YAW_DEG := 45.0
const DISTANCE := 40.0
const ORTHO_SIZE := 22.0
const FOLLOW_RATE := 6.0

@export var target_path: NodePath
## XZ rectangle (x, z, width, depth) the look-at point is clamped to. A zero-size rect means unbounded.
@export var bounds: Rect2 = Rect2()

var _target: Node3D
@onready var _camera: Camera3D = $Camera3D

func _ready() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = ORTHO_SIZE
	var basis := Basis(Vector3.UP, deg_to_rad(YAW_DEG)) * Basis(Vector3.RIGHT, deg_to_rad(PITCH_DEG))
	_camera.transform = Transform3D(basis, basis * Vector3(0.0, 0.0, DISTANCE))
	if _target == null and not target_path.is_empty():
		_target = get_node_or_null(target_path) as Node3D
	if _target != null:
		snap_to_target()

func set_target(node: Node3D) -> void:
	_target = node

func snap_to_target() -> void:
	if _target != null:
		position = _clamped_target()

## Current clamped look-at point.
func focus_point() -> Vector3:
	return position

func _process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	position = position.lerp(_clamped_target(), 1.0 - exp(-FOLLOW_RATE * delta))

func _clamped_target() -> Vector3:
	var p := _target.global_position if _target.is_inside_tree() else _target.position
	var focus := Vector3(p.x, 0.0, p.z)
	if bounds.size != Vector2.ZERO:
		focus.x = clampf(focus.x, bounds.position.x, bounds.end.x)
		focus.z = clampf(focus.z, bounds.position.y, bounds.end.y)
	return focus
