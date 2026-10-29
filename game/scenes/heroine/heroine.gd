class_name Heroine
extends CharacterBody3D
## The dreamer-botanist: iso-relative movement, aim from mouse/stick/move, nightmare hits.

signal nightmare_hit

const SPEED := 5.0
## Screen-up on the ground for the fixed iso camera (yaw 45 deg); screen-right is (1, -1).
const SCREEN_UP := Vector2(-1, -1)
const SCREEN_RIGHT := Vector2(1, -1)
const AIM_RAY_LENGTH := 200.0
## An accepted nightmare hit slides the heroine this far away from the nightmare...
const KNOCKBACK_DISTANCE := 1.5
## ...over this many seconds.
const KNOCKBACK_DURATION := 0.15
## The heroine is kept this far inside the island outline (NightSession clamps with it too).
const EDGE_MARGIN := 0.4

var aim_dir: Vector2 = Vector2(0, 1) ## unit XZ, never zero
var aim_source: AimAssist.Source = AimAssist.Source.MOVE
var lucidity: Lucidity ## injected by NightSession
var island: IslandShape ## injected by NightSession; clamps knockbacks

var _knockback_velocity: Vector3 = Vector3.ZERO
var _knockback_left: float = 0.0

var _mouse_moved: bool = false
@onready var _visual: Node = $Visual

func _ready() -> void:
	add_to_group("heroine")
	_apply_facing()
	var belt := get_node_or_null("ToolBelt") as ToolBelt
	if belt != null and _visual != null and _visual.has_method("play_swing"):
		belt.tool_used.connect(func(_tool: ToolData) -> void: _visual.call("play_swing"))

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
	if _knockback_left > 0.0:
		var dt := minf(_delta, _knockback_left)
		_knockback_left -= dt
		velocity = Vector3.ZERO
		move_and_collide(_knockback_velocity * dt) # input ignored during the slide
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

## Nightmare contact from a nightmare at from_xz (XZ). Returns true when the hit is accepted
## (not invulnerable); an accepted hit with a source position knocks the heroine back.
func take_nightmare_hit(from_xz: Variant = null) -> bool:
	if lucidity == null:
		return false
	if not lucidity.take_hit(Time.get_ticks_msec() / 1000.0):
		return false
	nightmare_hit.emit()
	if _visual != null and _visual.has_method("blink_hurt"):
		_visual.call("blink_hurt")
	if from_xz is Vector2:
		knock_back_from(from_xz)
	return true

## Starts a KNOCKBACK_DISTANCE slide away from from_xz, clamped inside the island.
func knock_back_from(from_xz: Vector2) -> void:
	var p := global_position if is_inside_tree() else position
	var here := Vector2(p.x, p.z)
	var dir := here - from_xz
	if dir.length_squared() < 1e-6:
		dir = -aim_dir
	var target := here + dir.normalized() * KNOCKBACK_DISTANCE
	if island != null:
		target = island.clamp_inside(island.push_out_of_obstacles(target, EDGE_MARGIN), EDGE_MARGIN)
	_knockback_velocity = Vector3(target.x - here.x, 0.0, target.y - here.y) / KNOCKBACK_DURATION
	_knockback_left = KNOCKBACK_DURATION

func is_knocked_back() -> bool:
	return _knockback_left > 0.0

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
