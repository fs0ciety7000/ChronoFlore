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

## 0 for P1 (the heroine in co-op), 1 for P2. Picks the p1_* / p2_* input actions.
@export var player_index: int = 0
## Visual (heroine_visual.tscn or hero2_visual.tscn, same interface). Null keeps the scene's own.
@export var visual_scene: PackedScene:
	set(value):
		visual_scene = value
		if is_node_ready():
			_apply_visual_scene()

var aim_dir: Vector2 = Vector2(0, 1) ## unit XZ, never zero
var aim_source: AimAssist.Source = AimAssist.Source.MOVE
## Keyboard-half players (shared keyboard, unplugged pad) aim AUTO: their walk, fully assisted.
var auto_aim: bool = false
## Only the keyboard-mouse player reads the mouse (P1 by default; NightSession sets it).
var uses_mouse: bool = true
## The pad this player listens to (DeviceAssignment: ALL_PADS, NO_PAD or a device id).
var pad_device: int = DeviceAssignment.ALL_PADS
var lucidity: Lucidity ## injected by NightSession
var island: IslandShape ## injected by NightSession; clamps knockbacks
## Game time in seconds for the invulnerability window (NightSession injects its physics time,
## which stops on pause and follows time_scale). Unset: this heroine's own physics time.
var time_source: Callable

var _immobile_left: float = 0.0
var _slow_left: float = 0.0
var _slow_factor: float = 1.0

var _knockback_velocity: Vector3 = Vector3.ZERO
var _knockback_left: float = 0.0

var _mouse_moved: bool = false
var _own_time: float = 0.0 ## physics seconds ticked by tick_status
@onready var _visual: Node = $Visual

func _ready() -> void: # group "heroine" comes from heroine.tscn
	if visual_scene != null:
		_apply_visual_scene()
	_apply_facing()
	var belt := get_node_or_null("ToolBelt") as ToolBelt
	# The lambdas read _visual at call time, so they follow a later visual swap.
	if belt != null:
		belt.tool_used.connect(func(_tool: ToolData) -> void:
			if _visual != null and _visual.has_method("play_swing"):
				_visual.call("play_swing"))
		belt.tool_changed.connect(func(tool: ToolData) -> void:
			if _visual != null and _visual.has_method("set_tool"):
				_visual.call("set_tool", tool))
		if _visual != null and _visual.has_method("set_tool"):
			_visual.call("set_tool", belt.current())

## This player's input action: "use_tool" -> &"p1_use_tool" (index 0) or &"p2_use_tool" (index 1).
func action(base: StringName) -> StringName:
	return StringName("p%d_%s" % [player_index + 1, base])

## Replaces the Visual child with an instance of visual_scene (no-op when already that scene).
func _apply_visual_scene() -> void:
	if visual_scene == null:
		return
	var old := get_node_or_null("Visual")
	if old != null and old.scene_file_path == visual_scene.resource_path:
		_visual = old
		return
	if old != null:
		remove_child(old)
		old.queue_free()
	var fresh := visual_scene.instantiate()
	fresh.name = "Visual"
	add_child(fresh)
	move_child(fresh, mini(1, get_child_count() - 1))
	_visual = fresh
	_apply_facing()
	var belt := get_node_or_null("ToolBelt") as ToolBelt
	if belt != null and _visual.has_method("set_tool"):
		_visual.call("set_tool", belt.current())

## Screen-space input (x right, y down, as Input.get_vector) to a unit-or-shorter XZ vector.
static func screen_to_world(v: Vector2) -> Vector2:
	return SCREEN_RIGHT.normalized() * v.x + SCREEN_UP.normalized() * -v.y

func facing() -> Vector2:
	return aim_dir

## True while this player's pad (any pad for ALL_PADS) is connected.
func has_pad() -> bool:
	var pads := Input.get_connected_joypads()
	if pad_device == DeviceAssignment.NO_PAD:
		return false
	if pad_device == DeviceAssignment.ALL_PADS:
		return not pads.is_empty()
	return pads.has(pad_device)

func _input(event: InputEvent) -> void:
	# The mouse belongs to P1 (keyboard-mouse); P2 aims with a stick or by walking.
	if player_index == 0 and uses_mouse and event is InputEventMouseMotion:
		_mouse_moved = true

func _physics_process(_delta: float) -> void:
	tick_status(_delta)
	var move := Input.get_vector(action(&"move_left"), action(&"move_right"), action(&"move_up"), action(&"move_down"))
	var stick := Input.get_vector(action(&"aim_left"), action(&"aim_right"), action(&"aim_up"), action(&"aim_down"))
	var w := screen_to_world(move)
	velocity = Vector3(w.x, 0.0, w.y) * move_speed()
	if _knockback_left > 0.0:
		var dt := minf(_delta, _knockback_left)
		_knockback_left -= dt
		velocity = Vector3.ZERO
		move_and_collide(_knockback_velocity * dt) # input ignored during the slide
	move_and_slide()
	update_aim(_mouse_moved, _mouse_ground_point(), stick, move, has_pad())
	_mouse_moved = false
	if _visual != null and _visual.has_method("set_walking"):
		_visual.call("set_walking", move.length() > 0.1 and move_speed() > 0.0)

## Per-frame aim update from already-sampled inputs. mouse_ground is a Vector3 or null.
func update_aim(mouse_moved: bool, mouse_ground: Variant, stick: Vector2, move: Vector2, pad_active: bool) -> void:
	if auto_aim:
		aim_source = AimAssist.Source.AUTO
	else:
		aim_source = AimAssist.pick_source(aim_source, mouse_moved, stick, move, pad_active)
	var dir := Vector2.ZERO
	match aim_source:
		AimAssist.Source.MOUSE:
			if mouse_ground is Vector3:
				var p: Vector3 = mouse_ground
				dir = Vector2(p.x - global_position.x, p.z - global_position.z)
		AimAssist.Source.STICK:
			dir = screen_to_world(stick)
		AimAssist.Source.MOVE, AimAssist.Source.AUTO:
			dir = screen_to_world(move)
	if dir.length_squared() > 1e-4:
		aim_dir = dir.normalized()
		_apply_facing()

## Nightmare contact from a nightmare at from_xz (XZ). Returns true when the hit is accepted
## (not invulnerable); an accepted hit with a source position knocks the heroine back.
func take_nightmare_hit(from_xz: Variant = null) -> bool:
	if lucidity == null:
		return false
	if not lucidity.take_hit_for(player_index, game_time()):
		return false
	nightmare_hit.emit()
	if _visual != null and _visual.has_method("blink_hurt"):
		_visual.call("blink_hurt")
	if from_xz is Vector2:
		knock_back_from(from_xz)
	return true

## Seconds of game (physics) time, never wall-clock: pauses and time_scale hold it.
func game_time() -> float:
	if time_source.is_valid():
		return float(time_source.call())
	return _own_time

## Starts a KNOCKBACK_DISTANCE slide away from from_xz, clamped inside the island.
func knock_back_from(from_xz: Vector2) -> void:
	var p := global_position if is_inside_tree() else position
	var here := Vector2(p.x, p.z)
	var dir := here - from_xz
	if dir.length_squared() < 1e-6:
		dir = -aim_dir
	var target := here + dir.normalized() * KNOCKBACK_DISTANCE
	if island != null:
		target = island.clamp_walkable(target, EDGE_MARGIN, EDGE_MARGIN)
	_knockback_velocity = Vector3(target.x - here.x, 0.0, target.y - here.y) / KNOCKBACK_DURATION
	_knockback_left = KNOCKBACK_DURATION

## Held by vines (Lierre-Jalousie): no walking for `seconds`. Keeps the longest remaining hold,
## never the sum, so overlapping rings cannot chain into a long lock.
func immobilize(seconds: float) -> void:
	_immobile_left = maxf(_immobile_left, seconds)

## In spores (Champi-Panique): walk at `factor` of the speed for `seconds`. Keeps the longest
## remaining duration and the strongest factor of the active slows, without stacking them.
func slow(factor: float, seconds: float) -> void:
	_slow_factor = minf(_slow_factor, factor) if _slow_left > 0.0 else factor
	_slow_left = maxf(_slow_left, seconds)

func is_immobilized() -> bool:
	return _immobile_left > 0.0

func is_slowed() -> bool:
	return _slow_left > 0.0

func immobilized_left() -> float:
	return _immobile_left

func slowed_left() -> float:
	return _slow_left

## Walking speed with the current status (immobilized: 0, slowed: SPEED x factor).
func move_speed() -> float:
	if is_immobilized():
		return 0.0
	return SPEED * (_slow_factor if is_slowed() else 1.0)

## Counts the immobilized / slowed timers down (called by _physics_process; tests call it).
func tick_status(delta: float) -> void:
	_own_time += delta
	_immobile_left = maxf(_immobile_left - delta, 0.0)
	_slow_left = maxf(_slow_left - delta, 0.0)
	if _slow_left <= 0.0:
		_slow_factor = 1.0

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
