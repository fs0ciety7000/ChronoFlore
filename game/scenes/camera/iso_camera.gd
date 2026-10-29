class_name IsoCamera
extends Node3D
## Fixed-angle orthographic follow camera. This node sits on the look-at point; the Camera3D
## child is offset along the iso view axis. The focus point is clamped to `bounds` (XZ).
## With several targets (co-op) it frames their barycentre and widens its ortho size with their
## spread (CoopRules.camera_size: ORTHO_SIZE up to x1.5).

const PITCH_DEG := -35.264
const YAW_DEG := 45.0
const DISTANCE := 40.0
const ORTHO_SIZE := 10.0
const FOLLOW_RATE := 6.0

@export var target_path: NodePath
## XZ rectangle (x, z, width, depth) the look-at point is clamped to. A zero-size rect means unbounded.
@export var bounds: Rect2 = Rect2()

var _targets: Array[Node3D] = []
@onready var _camera: Camera3D = $Camera3D

func _ready() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = ORTHO_SIZE
	var basis := Basis(Vector3.UP, deg_to_rad(YAW_DEG)) * Basis(Vector3.RIGHT, deg_to_rad(PITCH_DEG))
	_camera.transform = Transform3D(basis, basis * Vector3(0.0, 0.0, DISTANCE))
	if _targets.is_empty() and not target_path.is_empty():
		var node := get_node_or_null(target_path) as Node3D
		if node != null:
			_targets.append(node)
	if not _targets.is_empty():
		snap_to_target()

func set_target(node: Node3D) -> void:
	_targets.clear()
	if node != null:
		_targets.append(node)

## Frames every node (co-op players): barycentre, ortho size from their spread.
func set_targets(nodes: Array[Node3D]) -> void:
	_targets = nodes.duplicate()

func snap_to_target() -> void:
	if _has_targets():
		position = _clamped_target()
		_camera.size = _wanted_size()

## Current clamped look-at point.
func focus_point() -> Vector3:
	return position

## Current orthographic size (ORTHO_SIZE in solo).
func ortho_size() -> float:
	return _camera.size

func _process(delta: float) -> void:
	if not _has_targets():
		return
	var k := 1.0 - exp(-FOLLOW_RATE * delta)
	position = position.lerp(_clamped_target(), k)
	_camera.size = lerpf(_camera.size, _wanted_size(), k)

func _has_targets() -> bool:
	for t in _targets:
		if t != null and is_instance_valid(t):
			return true
	return false

func _ground_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for t in _targets:
		if t != null and is_instance_valid(t):
			var p := t.global_position if t.is_inside_tree() else t.position
			out.append(Vector2(p.x, p.z))
	return out

## ORTHO_SIZE widened by the largest distance between two targets.
func _wanted_size() -> float:
	var points := _ground_points()
	var spread := 0.0
	for i in points.size():
		for j in range(i + 1, points.size()):
			spread = maxf(spread, points[i].distance_to(points[j]))
	return CoopRules.camera_size(ORTHO_SIZE, spread)

func _clamped_target() -> Vector3:
	var points := _ground_points()
	var sum := Vector2.ZERO
	for p in points:
		sum += p
	var mid := sum / maxf(points.size(), 1.0)
	var focus := Vector3(mid.x, 0.0, mid.y)
	if bounds.size != Vector2.ZERO:
		focus.x = clampf(focus.x, bounds.position.x, bounds.end.x)
		focus.z = clampf(focus.z, bounds.position.y, bounds.end.y)
	return focus
