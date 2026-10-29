class_name Plant
extends CharacterBody3D
## A capturable (or nightmare) plant: state machine, flight, tool hits and placeholder visual.
## IslandShape is the only source of truth for edges: physics never decides a fall.

enum State { WANDER, ALERT, FLEE, PANIC, BURROWED, EMERGING, CAPTURED, ESCAPED }

signal captured(plant: Plant)
signal escaped(plant: Plant)
signal fell_asleep(plant: Plant) ## relays Torpor.fell_asleep (herbarium page for Ronce)

## Heroine closer than this alerts a wandering plant (plateau is only ~20 x 17.5 m).
const ALERT_RADIUS := 5.0
## Heroine farther than this for CALM_DURATION calms the plant down (back to WANDER).
const CALM_DISTANCE := 9.0
const CALM_DURATION := 4.0
## Short tremble before fleeing.
const ALERT_DURATION := 0.25
## Non-panicked plants are kept this far inside the outline every frame.
const EDGE_MARGIN := 0.3
## A panicked plant this close to the edge (or outside) jumps off.
const ESCAPE_EDGE_DISTANCE := 0.2
const FALL_DURATION := 1.0
const FALL_GRAVITY := 12.0
const BURROW_DURATION := 1.2
const EMERGE_DURATION := 1.0
const EMERGE_MIN_DISTANCE := 4.0
const EMERGE_MAX_DISTANCE := 6.0
## Stalker contact radius with the heroine.
const CONTACT_DISTANCE := 0.9
const WANDER_SPEED_SCALE := 0.35
const WANDER_HOP_MIN := 1.5
const WANDER_HOP_MAX := 3.5
const WANDER_PAUSE_MIN := 0.8
const WANDER_PAUSE_MAX := 2.0
const WANDER_MARGIN := 1.0
## Missed net: short startled sprint.
const STARTLE_DURATION := 0.8
const STARTLE_BOOST := 1.5
const CAPTURE_FREE_DELAY := 0.3
## Emission energy at plant_glow = 1.
const GLOW_ENERGY := 0.8
## Hop while moving.
const BOB_HEIGHT := 0.06
const BOB_FREQ := 6.0
## Gentle breathing bob while idle.
const IDLE_BOB_HEIGHT := 0.035
const IDLE_BOB_FREQ := 2.4
const TREMBLE_AMPLITUDE := 0.04
const SLEEP_SQUASH := 0.6

var species: PlantSpecies
var torpor: Torpor
var state: State = State.WANDER:
	set = _set_state
var speed_multiplier: float = 1.0

var island: IslandShape
var _behavior: PlantBehavior
var _rng := RandomNumberGenerator.new()
var _materials: Array[StandardMaterial3D] = []
var _glow: float = 0.0 ## last plant_glow, reapplied whenever the visual is rebuilt

var _has_threat: bool = false
var _threat: Vector2 = Vector2.ZERO
var _aim: Vector2 = Vector2.ZERO

var _state_time: float = 0.0
var _panic_time: float = 0.0
var _calm_time: float = 0.0
var _startle_left: float = 0.0
var _wander_target: Vector2 = Vector2.ZERO
var _wander_has_target: bool = false
var _wander_pause: float = 0.0
var _fall_speed: float = 0.0
var _fall_dir: Vector2 = Vector2.ZERO
var _anim_t: float = 0.0
var _moving: bool = false

func _init() -> void:
	torpor = Torpor.new()
	torpor.fell_asleep.connect(func() -> void: fell_asleep.emit(self))
	_rng.randomize()
	_anim_t = _rng.randf() * TAU # desynchronise idle bobs

func _ready() -> void:
	add_to_group("plants")

func setup(p_species: PlantSpecies, p_island: IslandShape, p_speed_multiplier: float) -> void:
	species = p_species
	island = p_island
	speed_multiplier = p_speed_multiplier
	_behavior = PlantBehavior.for_species(species)
	_build_visual()

## Heroine position and aim direction (XZ), fed every frame by the night session.
func set_threat(position_xz: Vector2, aim_dir: Vector2) -> void:
	_has_threat = true
	_threat = position_xz
	_aim = aim_dir

## TORPOR -> dart, PIN -> pin, CAPTURE -> net. Returns true only on a capture.
func hit_by_tool(effect: ToolData.Effect) -> bool:
	if state == State.BURROWED or state == State.CAPTURED or state == State.ESCAPED:
		return false
	match effect:
		ToolData.Effect.TORPOR:
			torpor.add_dart()
			_alert_from_hit()
		ToolData.Effect.PIN:
			torpor.pin()
			_alert_from_hit()
		ToolData.Effect.CAPTURE:
			if species.capturable and torpor.net_can_capture(is_emerging()):
				_capture()
				return true
			_alert_from_hit()
			if not _is_stalker():
				startle()
	return false

## Short sprint boost after a missed net; only a fleeing or panicked plant reacts.
func startle() -> void:
	if state == State.FLEE or state == State.PANIC:
		_startle_left = STARTLE_DURATION

func is_startled() -> bool:
	return _startle_left > 0.0

func is_emerging() -> bool:
	return state == State.EMERGING

func has_threat() -> bool:
	return _has_threat

func threat_xz() -> Vector2:
	return _threat

func aim_dir() -> Vector2:
	return _aim

func panic_time() -> float:
	return _panic_time

func xz() -> Vector2:
	var p := global_position if is_inside_tree() else position
	return Vector2(p.x, p.z)

## Unit flee direction from the heroine (towards the edge in PANIC); zero without a threat.
func flee_direction() -> Vector2:
	if not _has_threat:
		return Vector2.ZERO
	return Steering.flee(xz(), _threat, island, state == State.PANIC)

## Pastel emission driven by the night palette's plant_glow (0..1).
func set_glow(value: float) -> void:
	_glow = value
	_apply_glow()

func _apply_glow() -> void:
	var value := _glow
	for mat in _materials:
		mat.emission_enabled = value > 0.001
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = maxf(value, 0.0) * GLOW_ENERGY

func _physics_process(delta: float) -> void:
	step(delta)

func _process(delta: float) -> void:
	_animate_visual(delta)

## One simulation tick (called by _physics_process; tests call it directly).
func step(delta: float) -> void:
	if species == null or state == State.CAPTURED:
		return
	if state == State.ESCAPED:
		_fall(delta)
		return
	torpor.tick(delta)
	_state_time += delta
	var dist := xz().distance_to(_threat) if _has_threat else INF
	var dir := Vector2.ZERO
	match state:
		State.WANDER:
			if _is_stalker():
				dir = _behavior.desired_velocity(self, delta) if _has_threat else _wander(delta)
				_check_contact(dist)
			else:
				dir = _wander(delta)
				if dist < ALERT_RADIUS:
					state = State.ALERT
		State.ALERT:
			if _state_time >= ALERT_DURATION:
				state = State.FLEE
		State.FLEE, State.PANIC:
			_panic_time += delta
			_calm_time = _calm_time + delta if dist > CALM_DISTANCE else 0.0
			if _calm_time >= CALM_DURATION:
				_panic_time = 0.0
				state = State.WANDER
			else:
				if state == State.FLEE and _panic_time >= species.panic_after:
					state = State.PANIC
				if state == State.FLEE and _behavior.should_burrow(self):
					state = State.BURROWED
				else:
					dir = _behavior.desired_velocity(self, delta)
		State.BURROWED:
			_panic_time += delta
			if _state_time >= BURROW_DURATION:
				_emerge()
		State.EMERGING:
			_panic_time += delta
			if _state_time >= EMERGE_DURATION:
				state = State.FLEE
	var speed := species.base_speed * speed_multiplier * torpor.speed_factor()
	if state == State.WANDER and not (_is_stalker() and _has_threat):
		speed *= WANDER_SPEED_SCALE
	if _startle_left > 0.0:
		_startle_left -= delta
		speed *= STARTLE_BOOST
	_move(dir * speed * delta)
	_keep_on_island()

func _is_stalker() -> bool:
	return species.behavior == PlantSpecies.Behavior.STALKER

func _set_state(value: State) -> void:
	if value == state:
		return
	state = value
	_state_time = 0.0
	if value == State.FLEE:
		_calm_time = 0.0
		if _behavior != null:
			_behavior.reset()
	var visual := get_node_or_null("Visual") as Node3D
	if visual != null:
		visual.visible = value != State.BURROWED
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		var off := value == State.BURROWED or value == State.CAPTURED or value == State.ESCAPED
		shape.set_deferred("disabled", off)

func _alert_from_hit() -> void:
	if not _is_stalker() and (state == State.WANDER or state == State.ALERT):
		state = State.FLEE

func _capture() -> void:
	state = State.CAPTURED
	captured.emit(self)
	var visual := get_node_or_null("Visual") as Node3D
	if is_inside_tree() and visual != null:
		var tween := create_tween()
		tween.tween_property(visual, "scale", Vector3.ONE * 0.01, CAPTURE_FREE_DELAY)
		tween.tween_callback(queue_free)

func _escape() -> void:
	_fall_dir = island.outward_normal(xz()) if island != null else Vector2.ZERO
	_fall_speed = 0.0
	state = State.ESCAPED
	escaped.emit(self)

func _fall(delta: float) -> void:
	_state_time += delta
	_fall_speed += FALL_GRAVITY * delta
	position += Vector3(_fall_dir.x, 0.0, _fall_dir.y) * species.base_speed * delta
	position.y -= _fall_speed * delta
	if _state_time >= FALL_DURATION and not is_queued_for_deletion():
		queue_free()

func _emerge() -> void:
	var dir := flee_direction()
	if dir == Vector2.ZERO:
		dir = Vector2.from_angle(_rng.randf() * TAU)
	var target := xz() + dir * _rng.randf_range(EMERGE_MIN_DISTANCE, EMERGE_MAX_DISTANCE)
	if island != null:
		target = island.clamp_inside(target, EDGE_MARGIN)
	_set_xz(target)
	state = State.EMERGING

func _check_contact(dist: float) -> void:
	if dist >= CONTACT_DISTANCE or torpor.is_asleep() or not is_inside_tree():
		return
	var heroine := get_tree().get_first_node_in_group("heroine")
	if heroine != null and heroine.has_method("take_nightmare_hit"):
		heroine.call("take_nightmare_hit")

func _wander(delta: float) -> Vector2:
	if _wander_pause > 0.0:
		_wander_pause -= delta
		return Vector2.ZERO
	var pos := xz()
	if not _wander_has_target or pos.distance_to(_wander_target) < 0.2:
		var target := pos + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(WANDER_HOP_MIN, WANDER_HOP_MAX)
		if island != null:
			target = island.clamp_inside(target, WANDER_MARGIN)
		_wander_target = target
		_wander_has_target = true
		_wander_pause = _rng.randf_range(WANDER_PAUSE_MIN, WANDER_PAUSE_MAX)
		return Vector2.ZERO
	return Steering.seek(pos, _wander_target)

func _move(motion: Vector2) -> void:
	_moving = motion.length_squared() > 1e-10
	if not _moving:
		return
	var m3 := Vector3(motion.x, 0.0, motion.y)
	if is_inside_tree():
		var col := move_and_collide(m3)
		if col != null:
			var rest := col.get_remainder().slide(col.get_normal())
			rest.y = 0.0
			move_and_collide(rest)
		global_position.y = 0.0
	else:
		position += m3
	var visual := get_node_or_null("Visual") as Node3D
	if visual != null:
		visual.rotation.y = atan2(motion.x, motion.y)

## Outside PANIC the plant is clamped inside the outline; in PANIC, reaching the edge means a jump.
func _keep_on_island() -> void:
	if island == null:
		return
	var pos := xz()
	if state == State.PANIC:
		var can_jump := torpor.speed_factor() > 0.0
		if can_jump and (not island.contains(pos) or island.distance_to_edge(pos) < ESCAPE_EDGE_DISTANCE):
			_escape()
		return
	var clamped := island.clamp_inside(pos, EDGE_MARGIN)
	if clamped != pos:
		_set_xz(clamped)

func _set_xz(p: Vector2) -> void:
	if is_inside_tree():
		global_position = Vector3(p.x, global_position.y, p.y)
	else:
		position = Vector3(p.x, position.y, p.y)

func _build_visual() -> void:
	var holder := get_node_or_null("Visual") as Node3D
	if holder == null:
		return
	for child in holder.get_children():
		child.queue_free()
	_materials.clear()
	if species == null or species.visual_scene == null:
		return
	var visual := species.visual_scene.instantiate()
	holder.add_child(visual)
	# Per-plant material copies so glow and tints never leak between instances.
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mat := mi.get_active_material(0) as StandardMaterial3D
		if mat == null:
			continue
		var copy := mat.duplicate() as StandardMaterial3D
		mi.material_override = copy
		_materials.append(copy)
	_apply_glow()

func _animate_visual(delta: float) -> void:
	var visual := get_node_or_null("Visual") as Node3D
	if visual == null or state == State.CAPTURED:
		return # the capture tween owns the visual's scale
	_anim_t += delta
	var offset := Vector3.ZERO
	var squash := 1.0
	if torpor.is_asleep():
		squash = SLEEP_SQUASH
	elif state == State.ALERT:
		offset.x = sin(_anim_t * 70.0) * TREMBLE_AMPLITUDE
	elif state != State.CAPTURED and state != State.ESCAPED:
		if _moving:
			offset.y = absf(sin(_anim_t * BOB_FREQ)) * BOB_HEIGHT * 2.0
		else:
			offset.y = (0.5 + 0.5 * sin(_anim_t * IDLE_BOB_FREQ)) * IDLE_BOB_HEIGHT
	visual.position = offset
	var sy := lerpf(visual.scale.y, squash, 1.0 - exp(-10.0 * delta))
	var sxz := 1.0 / sqrt(maxf(sy, 0.01))
	visual.scale = Vector3(sxz, sy, sxz)
