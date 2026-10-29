class_name Hazard
extends Node3D
## A hostile attack on the ground: a soft sign first (telegraph, at least MIN_TELEGRAPH), then
## the impact, which strikes the heroine if she is still within `radius`, then a short linger.
## Subclasses set the colours, add their own visuals and decide what a strike does (_strike).
## Lives next to the plants (NightSession's Plants root), so a frozen night freezes it too.

## Emitted when the impact (or a lingering cloud) affects the target.
signal struck(target: Node3D)

## Readability rule: every attack is announced at least this long before it lands.
const MIN_TELEGRAPH := 0.6
## The sign pulses faster as the impact nears (rad/s of the shader's sine).
const PULSE_RATE_START := 5.0
const PULSE_RATE_END := 16.0

## Strike radius around the hazard (XZ, metres).
@export var radius: float = 1.0:
	set(value):
		radius = value
		if mark != null:
			mark.resize_disc(value)
## Seconds the hazard stays after the impact (vines, cloud) before freeing itself.
@export var linger: float = 0.4
@export var rim_color: Color = Color(1.0, 0.45, 0.5)
@export var fill_color: Color = Color(1.0, 0.72, 0.74)

var telegraph_time: float = MIN_TELEGRAPH
var elapsed: float = 0.0
var mark: GroundMark

var _impacted: bool = false

func _ready() -> void:
	_ensure_mark()

## Places the hazard on the ground at `at` and starts its telegraph (never under 0.6 s).
func setup(at: Vector3, telegraph: float) -> void:
	telegraph_time = maxf(telegraph, MIN_TELEGRAPH)
	elapsed = 0.0
	_impacted = false
	if is_inside_tree():
		global_position = at
	else:
		position = at
	_ensure_mark()
	_update_visual(0.0)

func _physics_process(delta: float) -> void:
	tick(delta)

## One simulation tick (called by _physics_process; tests call it directly).
func tick(delta: float) -> void:
	if is_queued_for_deletion():
		return
	elapsed += delta
	if not _impacted:
		if elapsed >= telegraph_time - 1e-6:
			_impacted = true
			_on_impact()
			var target := target_in_radius()
			if target != null and _strike(target):
				struck.emit(target)
		_update_visual(clampf(elapsed / telegraph_time, 0.0, 1.0))
		return
	_linger_tick(delta)
	_update_visual(1.0)
	if elapsed >= telegraph_time + linger and not is_queued_for_deletion():
		queue_free()

func is_telegraphing() -> bool:
	return not _impacted

func has_impacted() -> bool:
	return _impacted

func time_to_impact() -> float:
	return maxf(telegraph_time - elapsed, 0.0)

func has_ground_mark() -> bool:
	return mark != null and mark.visible

func center_xz() -> Vector2:
	var p := global_position if is_inside_tree() else position
	return Vector2(p.x, p.z)

## The heroine if she stands within `radius`, else null.
func target_in_radius() -> Node3D:
	if not is_inside_tree():
		return null
	var heroine := get_tree().get_first_node_in_group("heroine") as Node3D
	if heroine == null:
		return null
	var h := Vector2(heroine.global_position.x, heroine.global_position.z)
	return heroine if h.distance_to(center_xz()) <= radius else null

## What the impact does to the target; true when it counts as a strike.
func _strike(_target: Node3D) -> bool:
	return true

## Visual switch at the impact (vines burst out, thorn lands, cloud puffs).
func _on_impact() -> void:
	pass

## Called every tick after the impact (lingering clouds keep affecting the heroine).
func _linger_tick(_delta: float) -> void:
	pass

## progress: 0 at setup, 1 at the impact and after.
func _update_visual(progress: float) -> void:
	if mark == null:
		return
	mark.set_progress(progress)
	mark.set_pulse_rate(lerpf(PULSE_RATE_START, PULSE_RATE_END, progress))
	if _impacted and linger > 0.0:
		mark.set_opacity(1.0 - clampf((elapsed - telegraph_time) / linger, 0.0, 1.0))

func _ensure_mark() -> void:
	if mark != null:
		return
	mark = GroundMark.disc(radius, rim_color, fill_color)
	mark.name = "Mark"
	add_child(mark)
