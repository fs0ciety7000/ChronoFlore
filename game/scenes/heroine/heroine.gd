class_name Heroine
extends CharacterBody3D
## The dreamer-botanist: iso-relative movement, aim from mouse/stick/move, nightmare hits.

signal nightmare_hit

const SPEED := 5.0
## Screen-up on the ground for the fixed iso camera (yaw 45 deg); screen-right is (1, -1).
const SCREEN_UP := Vector2(-1, -1)
const SCREEN_RIGHT := Vector2(1, -1)
const AIM_RAY_LENGTH := 200.0

var aim_dir: Vector2 = Vector2(0, 1) ## unit XZ, never zero
var aim_source: AimAssist.Source = AimAssist.Source.MOVE
var lucidity: Lucidity ## injected by NightSession

var _mouse_moved: bool = false
@onready var _visual: Node = $Visual

func _ready() -> void:
	add_to_group("heroine")
	_apply_facing()

## Screen-space input (x right, y down, as Input.get_vector) to a unit-or-shorter XZ vector.
static func screen_to_world(v: Vector2) -> Vector2:
	return SCREEN_RIGHT.normalized() * v.x + SCREEN_UP.normalized() * -v.y

func facing() -> Vector2:
	return aim_dir

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_moved = true

func _physics_process(_delta: float) -> void:
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	var w := screen_to_world(move)
	velocity = Vector3(w.x, 0.0, w.y) * SPEED
	move_and_slide()
	update_aim(_mouse_moved, _mouse_ground_point(), stick, move, not Input.get_connected_joypads().is_empty())
	_mouse_moved = false
	if _visual != null and _visual.has_method("set_walking"):
		_visual.call("set_walking", move.length() > 0.1)

## Per-frame aim update from already-sampled inputs. mouse_ground is a Vector3 or null.
func update_aim(mouse_moved: bool, mouse_ground: Variant, stick: Vector2, move: Vector2, pad_active: bool) -> void:
	aim_source = AimAssist.pick_source(aim_source, mouse_moved, stick, move, pad_active)
	var dir := Vector2.ZERO
	match aim_source:
		AimAssist.Source.MOUSE:
			if mouse_ground is Vector3:
				var p: Vector3 = mouse_ground
				dir = Vector2(p.x - global_position.x, p.z - global_position.z)
		AimAssist.Source.STICK:
			dir = screen_to_world(stick)
		AimAssist.Source.MOVE:
			dir = screen_to_world(move)
	if dir.length_squared() > 1e-4:
		aim_dir = dir.normalized()
		_apply_facing()

func take_nightmare_hit() -> void:
	if lucidity == null:
		return
	if lucidity.take_hit(Time.get_ticks_msec() / 1000.0):
		nightmare_hit.emit()
		if _visual != null and _visual.has_method("blink_hurt"):
			_visual.call("blink_hurt")

func _apply_facing() -> void:
	if _visual is Node3D:
		(_visual as Node3D).rotation.y = atan2(aim_dir.x, aim_dir.y)

## Cursor projected on the y = 0 plane, or null without a camera (headless).
func _mouse_ground_point() -> Variant:
	var viewport := get_viewport()
	if viewport == null:
		return null
	var cam := viewport.get_camera_3d()
	if cam == null:
		return null
	var mouse := viewport.get_mouse_position()
	return Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse))
