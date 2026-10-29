class_name BehaviorCharger
extends PlantBehavior
## Croque-Colère: stalks the heroine; once she is within TRIGGER_DISTANCE it crouches for
## WINDUP_TIME over a lane drawn on the ground (the telegraph), then charges in a straight line
## locked at the start of the wind-up. A side-step dodges it. Only the charge hurts on contact.

const TRIGGER_DISTANCE := 6.0
const WINDUP_TIME := 0.8
const CHARGE_SPEED := 9.0
const CHARGE_DISTANCE := 6.0
## Between two charges (from the start of a charge).
const COOLDOWN := 4.0
## Delay before the first wind-up after spawning or waking.
const FIRST_COOLDOWN := 1.0
const LANE_WIDTH := 1.1
const LANE_RIM := Color(1.0, 0.42, 0.5)
const LANE_FILL := Color(1.0, 0.7, 0.72)

enum Phase { STALK, WINDUP, CHARGE }

var _phase: Phase = Phase.STALK
var _time: float = 0.0
var _cooldown: float = FIRST_COOLDOWN
var _dir: Vector2 = Vector2.ZERO
var _travelled: float = 0.0
var _lane: GroundMark
var _disabled: bool = false ## asleep or pinned on the last tick

func reset() -> void:
	_end_attack()

func contact_hurts() -> bool:
	return _phase == Phase.CHARGE

func faces_threat() -> bool:
	return _phase == Phase.STALK

func desired_velocity(plant: Plant, delta: float) -> Vector2:
	if not plant.can_attack():
		_end_attack()
		_disabled = true
		return Vector2.ZERO
	if _disabled: # just woke up (or freed from the harpoon): no instant wind-up
		_disabled = false
		_cooldown = maxf(_cooldown, FIRST_COOLDOWN)
	_cooldown -= delta
	match _phase:
		Phase.WINDUP:
			_time += delta
			if _lane != null:
				_lane.set_progress(_time / WINDUP_TIME)
			if _time >= WINDUP_TIME - 1e-6:
				_phase = Phase.CHARGE
				_travelled = 0.0
			return Vector2.ZERO
		Phase.CHARGE:
			var speed := plant.ground_speed()
			var step := minf(CHARGE_SPEED * plant.torpor.speed_factor() * delta, CHARGE_DISTANCE - _travelled)
			_travelled += step
			if _lane != null:
				_lane.set_opacity(1.0 - _travelled / CHARGE_DISTANCE)
			if _travelled >= CHARGE_DISTANCE - 1e-6:
				_end_attack()
			if speed <= 0.0 or delta <= 0.0:
				return Vector2.ZERO
			return _dir * (step / (speed * delta))
	var to := plant.threat_xz() - plant.xz()
	if _cooldown <= 0.0 and to.length() <= TRIGGER_DISTANCE and to.length_squared() > 1e-6:
		_start_windup(plant, to.normalized())
		return Vector2.ZERO
	return Steering.seek(plant.xz(), plant.threat_xz())

func _start_windup(plant: Plant, dir: Vector2) -> void:
	_phase = Phase.WINDUP
	_time = 0.0
	_dir = dir
	_cooldown = COOLDOWN + WINDUP_TIME
	_lane = GroundMark.lane(CHARGE_DISTANCE, LANE_WIDTH, LANE_RIM, LANE_FILL)
	_lane.name = "ChargeLane"
	plant.add_effect(_lane)
	var p := plant.ground_point()
	if _lane.is_inside_tree():
		_lane.global_position = p
		_lane.reset_physics_interpolation()
	else:
		_lane.position = p
	_lane.rotation = Vector3(0.0, atan2(dir.x, dir.y), 0.0)
	plant.play_attack(WINDUP_TIME)

func _end_attack() -> void:
	_phase = Phase.STALK
	if _lane != null and is_instance_valid(_lane):
		_lane.queue_free()
	_lane = null
