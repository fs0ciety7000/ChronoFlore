class_name BehaviorShyApproach
extends PlantBehavior
## Câlinette: walks up to the heroine, hesitates, then hops back at the last moment. The net
## picks her without darts while she approaches or hesitates; she never takes her eyes off her.

enum Phase { APPROACH, HESITATE, HOP, REST }

## Stops this close to the heroine.
const APPROACH_DISTANCE := 2.5
## Approach speed, as a fraction of the species speed.
const APPROACH_FACTOR := 0.6
## Blushing pause at APPROACH_DISTANCE before the hop (the last picking moment).
const HESITATE_TIME := 0.35
const HOP_DISTANCE := 4.0
const HOP_TIME := 0.45
## Apex of the hop arc of the model (visual only).
const HOP_HEIGHT := 0.45
## Pause after landing before walking up again.
const REST_TIME := 1.0
## Hops end this far inside the outline.
const HOP_EDGE_MARGIN := 0.5

var phase: Phase = Phase.APPROACH
var _t: float = 0.0
var _hop_dir: Vector2 = Vector2.ZERO
var _hop_factor: float = 0.0

func reset() -> void:
	phase = Phase.APPROACH
	_t = 0.0

func desired_velocity(plant: Plant, delta: float) -> Vector2:
	if plant.state == Plant.State.PANIC:
		return plant.flee_direction()
	if not plant.has_threat():
		return Vector2.ZERO
	_t += delta
	var dist := plant.xz().distance_to(plant.threat_xz())
	match phase:
		Phase.APPROACH:
			if dist <= APPROACH_DISTANCE:
				_enter(Phase.HESITATE)
				return Vector2.ZERO
			# never overshoot the stop distance in one frame
			var step := plant.ground_speed() * APPROACH_FACTOR * delta
			var factor := APPROACH_FACTOR
			if step > dist - APPROACH_DISTANCE and step > 0.0:
				factor *= (dist - APPROACH_DISTANCE) / step
			return Steering.seek(plant.xz(), plant.threat_xz()) * factor
		Phase.HESITATE:
			if _t >= HESITATE_TIME:
				_start_hop(plant)
				return _hop_dir * _hop_factor
			return Vector2.ZERO
		Phase.HOP:
			if _t >= HOP_TIME or plant.ground_speed() <= 0.0:
				_enter(Phase.REST)
				return Vector2.ZERO
			return _hop_dir * _hop_factor
		Phase.REST:
			if _t >= REST_TIME:
				_enter(Phase.APPROACH)
	return Vector2.ZERO

func net_window(_plant: Plant) -> bool:
	return phase == Phase.APPROACH or phase == Phase.HESITATE

func hover_height(_plant: Plant) -> float:
	if phase != Phase.HOP:
		return 0.0
	return sin(PI * clampf(_t / HOP_TIME, 0.0, 1.0)) * HOP_HEIGHT

func faces_threat() -> bool:
	return true

func _enter(p: Phase) -> void:
	phase = p
	_t = 0.0

## Backwards hop away from the heroine, landing inside the island and out of the pond.
func _start_hop(plant: Plant) -> void:
	_enter(Phase.HOP)
	var from := plant.xz()
	var dir := plant.flee_direction()
	var target := from + dir * HOP_DISTANCE
	if plant.island != null:
		target = plant.island.clamp_walkable(target, Plant.EDGE_MARGIN + HOP_EDGE_MARGIN, Plant.OBSTACLE_MARGIN)
	var v := target - from
	_hop_dir = v.normalized() if v.length_squared() > 1e-8 else Vector2.ZERO
	var speed := plant.ground_speed()
	_hop_factor = v.length() / (HOP_TIME * speed) if speed > 0.0 else 0.0
