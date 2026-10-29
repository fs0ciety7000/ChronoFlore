class_name Plant
extends CharacterBody3D
## A capturable (or nightmare) plant: state machine, flight, tool hits and its hand-made model
## (PlantModelVisual), whose animation follows the state.
## IslandShape is the only source of truth for edges: physics never decides a fall.

enum State { WANDER, ALERT, FLEE, PANIC, BURROWED, EMERGING, CAPTURED, ESCAPED }

signal captured(plant: Plant)
signal escaped(plant: Plant)
signal fell_asleep(plant: Plant) ## relays Torpor.fell_asleep
## A hostile launched a telegraphed attack (thorn, vine ring, spore cloud).
signal hazard_spawned(hazard: Hazard)

## Heroine closer than this alerts a wandering plant: a careful approach to ~4 m is possible.
const ALERT_RADIUS := 4.0
## Heroine farther than this for CALM_DURATION calms the plant down (back to WANDER);
## reachable on the ~37 x 34 m meadow.
const CALM_DISTANCE := 10.0
const CALM_DURATION := 4.0
## Short tremble before fleeing.
const ALERT_DURATION := 0.25
## Non-panicked plants are kept this far inside the outline every frame.
const EDGE_MARGIN := 0.3
## A panicked plant this close to the edge (or outside) jumps off.
const ESCAPE_EDGE_DISTANCE := 0.2
## Seconds of falling (after the visible edge) before the plant is freed.
const FALL_DURATION := 1.0
const FALL_GRAVITY := 12.0
## Minimum ground speed while running off the island.
const ESCAPE_MIN_SPEED := 2.5
const BURROW_DURATION := 1.2
const EMERGE_DURATION := 1.0
const EMERGE_MIN_DISTANCE := 4.0
const EMERGE_MAX_DISTANCE := 6.0
## Hostile contact radius with the heroine.
const CONTACT_DISTANCE := 0.9
## After an accepted contact hit the hostile stays still this long, so contact cannot chain.
const CONTACT_STUN_DURATION := 1.0
## Wander and emerge targets keep this distance to island obstacles (the pond).
const OBSTACLE_MARGIN := 0.4
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
## Small hop while wandering between targets (the model plays Idle; Move has its own hops).
const BOB_HEIGHT := 0.06
const BOB_FREQ := 6.0
const TREMBLE_AMPLITUDE := 0.04
## How fast the model follows the behavior's hover height (hop arc, float, dive), 1/s.
const HOVER_RATE := 14.0

var species: PlantSpecies
var torpor: Torpor
var state: State = State.WANDER:
	set = _set_state
var speed_multiplier: float = 1.0

var island: IslandShape
var _behavior: PlantBehavior
var _rng := RandomNumberGenerator.new()
var _model: PlantModelVisual
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
var _fall_travel: float = 0.0 ## ground distance run outward since the escape
var _anim_t: float = 0.0
var _moving: bool = false
var _stun_left: float = 0.0
var _hidden: bool = false ## last is_hidden(), to switch the collider when it changes
var _hover: float = 0.0 ## smoothed model height above the ground

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
	_hover = hover_height()
	_build_visual()

## Heroine position and aim direction (XZ), fed every frame by the night session.
func set_threat(position_xz: Vector2, aim_dir: Vector2) -> void:
	_has_threat = true
	_threat = position_xz
	_aim = aim_dir

## TORPOR -> dart, PIN -> pin, CAPTURE -> net. Returns true only on a capture.
## A hidden plant ignores every tool; an airborne one dodges the net (darts still hit).
## A hostile is netted only if it is asleep at the moment of the hit (never "on waking").
func hit_by_tool(effect: ToolData.Effect) -> bool:
	if state == State.BURROWED or state == State.CAPTURED or state == State.ESCAPED or is_hidden():
		return false
	match effect:
		ToolData.Effect.TORPOR:
			torpor.add_dart()
			_alert_from_hit()
		ToolData.Effect.PIN:
			torpor.pin()
			_alert_from_hit()
		ToolData.Effect.CAPTURE:
			if is_airborne():
				return false
			if _can_net():
				_capture()
				return true
			_alert_from_hit()
			if not is_hostile():
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

## Mid-hop, out of the net's reach (Souffloine).
func is_airborne() -> bool:
	return _behavior != null and _behavior.is_airborne()

## In the pond, ignored by every tool (Mélancolys).
func is_hidden() -> bool:
	return _behavior != null and _behavior.is_hidden()

## True while the net captures without darts: an emerging Timidelle, an approaching Câlinette.
func can_net_without_torpor() -> bool:
	if is_emerging():
		return true
	return _behavior != null and state == State.FLEE and _behavior.net_window(self)

## Target height of the model above the ground (the plant body itself stays on the ground).
func hover_height() -> float:
	return _behavior.hover_height(self) if _behavior != null else 0.0

## Ground speed without the startle boost (m/s): what a behavior's speed factor multiplies.
func ground_speed() -> float:
	return species.base_speed * speed_multiplier * torpor.speed_factor()

## Moves the plant on the XZ plane (behaviors: dive into and out of the pond).
func place_xz(p: Vector2) -> void:
	_set_xz(p)

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
	if _model != null:
		_model.set_glow(value)

func _physics_process(delta: float) -> void:
	step(delta)

func _process(delta: float) -> void:
	_animate_visual(delta)

func is_hostile() -> bool:
	return species != null and species.hostile

## A hostile attacks only while awake and free (not asleep, not pinned by the harpoon).
func can_attack() -> bool:
	return not torpor.is_asleep() and not torpor.is_pinned()

## Adds a hazard next to the plant (same parent: NightSession's Plants root) and starts it.
func spawn_hazard(hazard: Hazard, at: Vector3, telegraph: float) -> Hazard:
	var parent := get_parent() if get_parent() != null else self
	parent.add_child(hazard)
	hazard.setup(at, telegraph)
	hazard_spawned.emit(hazard)
	return hazard

## True while a hostile announces its attack (Croque's wind-up, Champi's swelling).
func is_telegraphing() -> bool:
	return _behavior != null and _behavior.is_telegraphing()

func is_charging() -> bool:
	return _behavior != null and _behavior.is_charging()

## The ground sign owned by the behavior (Croque's lane), or null.
func telegraph_mark() -> GroundMark:
	return _behavior.telegraph_mark() if _behavior != null else null

## Adds a world-placed effect (ground sign) that dies with the plant but does not follow it.
func add_effect(node: Node3D) -> void:
	node.top_level = true
	add_child(node)

## Plays the model's Attack so that its strike lands `impact_in` seconds from now (0: at once).
func play_attack(impact_in: float = 0.0) -> void:
	if _model != null:
		_model.play_attack(impact_in)

## True while a hostile rests after an accepted contact hit.
func is_stunned() -> bool:
	return _stun_left > 0.0

## One simulation tick (called by _physics_process; tests call it directly).
func step(delta: float) -> void:
	if species == null or state == State.CAPTURED:
		return
	if state == State.ESCAPED:
		_fall(delta)
		return
	torpor.tick(delta)
	if is_hidden():
		_behavior.tick_hidden(self, delta)
		_update_hidden()
		return
	_sync_animation()
	_state_time += delta
	var dist := xz().distance_to(_threat) if _has_threat else INF
	var dir := Vector2.ZERO
	match state:
		State.WANDER:
			if is_hostile():
				if _stun_left > 0.0:
					_stun_left -= delta
				elif _has_threat:
					dir = _behavior.desired_velocity(self, delta)
					_check_contact(dist)
				elif _behavior.wanders():
					dir = _wander(delta)
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
	if state == State.WANDER and not (is_hostile() and _has_threat):
		speed *= WANDER_SPEED_SCALE
	if _startle_left > 0.0:
		_startle_left -= delta
		speed *= STARTLE_BOOST
	_move(dir * speed * delta)
	_keep_on_island()
	_update_hidden()

func _can_net() -> bool:
	if not species.capturable:
		return false
	if is_hostile():
		return torpor.is_asleep()
	return torpor.net_can_capture(can_net_without_torpor())

func _set_state(value: State) -> void:
	if value == state:
		return
	var was_fleeing := state == State.FLEE
	state = value
	_state_time = 0.0
	if value == State.FLEE:
		_calm_time = 0.0
	# A flight cycle (hop, approach) never outlives the flight; FLEE -> PANIC carries on.
	if _behavior != null and (value == State.FLEE or not (value == State.PANIC and was_fleeing)):
		_behavior.reset()
	var visual := get_node_or_null("Visual") as Node3D
	if visual != null:
		visual.visible = value != State.BURROWED
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		var off := value == State.BURROWED or value == State.CAPTURED or value == State.ESCAPED
		shape.set_deferred("disabled", off)
	_sync_animation()

## Collider off while hidden in the pond (the model stays, sunk to a floating lily).
func _update_hidden() -> void:
	var hidden := is_hidden()
	if hidden == _hidden:
		return
	_hidden = hidden
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		shape.set_deferred("disabled", hidden)
	_sync_animation()

## Idle/Move/Sleep/Caught on the model, from the state and the torpor.
func _sync_animation() -> void:
	if _model != null:
		_model.play_state(State.WANDER if is_hidden() else state, torpor.is_asleep())

func _alert_from_hit() -> void:
	if not is_hostile() and (state == State.WANDER or state == State.ALERT):
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
	_fall_travel = 0.0
	state = State.ESCAPED
	escaped.emit(self)

## Runs outward on the ground until past the visible cliff edge (island.drop_inset), then drops.
func _fall(delta: float) -> void:
	var step_len := maxf(species.base_speed, ESCAPE_MIN_SPEED) * delta
	position += Vector3(_fall_dir.x, 0.0, _fall_dir.y) * step_len
	_fall_travel += step_len
	var drop_inset := island.drop_inset if island != null else 0.0
	if _fall_travel < drop_inset:
		_state_time = 0.0 # the fall timer starts at the edge
		return
	_state_time += delta
	_fall_speed += FALL_GRAVITY * delta
	position.y -= _fall_speed * delta
	if _state_time >= FALL_DURATION and not is_queued_for_deletion():
		queue_free()

## Ground distance run outward since the escape.
func fall_travel() -> float:
	return _fall_travel

func _emerge() -> void:
	var dir := flee_direction()
	if dir == Vector2.ZERO:
		dir = Vector2.from_angle(_rng.randf() * TAU)
	var target := xz() + dir * _rng.randf_range(EMERGE_MIN_DISTANCE, EMERGE_MAX_DISTANCE)
	if island != null:
		target = island.clamp_walkable(target, EDGE_MARGIN, OBSTACLE_MARGIN)
	_set_xz(target)
	state = State.EMERGING

func _check_contact(dist: float) -> void:
	if dist >= CONTACT_DISTANCE or torpor.is_asleep() or not is_inside_tree():
		return
	var heroine := get_tree().get_first_node_in_group("heroine")
	if heroine != null and heroine.has_method("take_nightmare_hit"):
		if heroine.call("take_nightmare_hit", xz()) == true:
			_stun_left = CONTACT_STUN_DURATION
			_behavior.reset() # a charge or a wind-up never outlives the hit
			if _model != null:
				_model.play_attack()

func _wander(delta: float) -> Vector2:
	if _wander_pause > 0.0:
		_wander_pause -= delta
		return Vector2.ZERO
	var pos := xz()
	if not _wander_has_target or pos.distance_to(_wander_target) < 0.2:
		var target := pos + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(WANDER_HOP_MIN, WANDER_HOP_MAX)
		if island != null:
			target = island.clamp_walkable(target, WANDER_MARGIN, OBSTACLE_MARGIN)
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
		var face := motion
		if _has_threat and _behavior != null and _behavior.faces_threat() and _threat != xz():
			face = _threat - xz()
		visual.rotation.y = atan2(face.x, face.y)

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
	_model = null
	if species == null or species.visual_scene == null:
		return
	var visual := species.visual_scene.instantiate()
	holder.add_child(visual)
	_model = visual as PlantModelVisual # owns per-plant material copies
	set_glow(_glow)
	_sync_animation()

func _animate_visual(delta: float) -> void:
	var visual := get_node_or_null("Visual") as Node3D
	if visual == null or state == State.CAPTURED:
		return # the capture tween owns the visual's scale
	_anim_t += delta
	_hover = lerpf(_hover, hover_height(), 1.0 - exp(-HOVER_RATE * delta))
	var offset := Vector3(0.0, _hover, 0.0) # sleep, flight and capture are the model's own animations
	if not torpor.is_asleep():
		if state == State.ALERT:
			offset.x = sin(_anim_t * 70.0) * TREMBLE_AMPLITUDE
		elif state == State.WANDER and _moving:
			offset.y += absf(sin(_anim_t * BOB_FREQ)) * BOB_HEIGHT * 2.0
	visual.position = offset
