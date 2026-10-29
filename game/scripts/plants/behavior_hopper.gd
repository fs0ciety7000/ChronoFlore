class_name BehaviorHopper
extends PlantBehavior
## Souffloine: flees in big carefree hops. In the air the net cannot reach her; on the ground,
## between hops, she can be netted (after darts). Outside PANIC every hop lands inside the island.

const HOP_DISTANCE := 3.0
const AIR_TIME := 0.7
## Time on the ground between two hops.
const GROUND_TIME := 0.5
## First hop comes quickly after the alert.
const FIRST_GROUND_TIME := 0.15
## Apex of the hop arc of the model (visual only).
const HOP_HEIGHT := 0.9
## Hops end this far inside the outline (on top of Plant.EDGE_MARGIN).
const HOP_EDGE_MARGIN := 0.5

var _air_left: float = 0.0
var _ground_left: float = FIRST_GROUND_TIME
var _hop_dir: Vector2 = Vector2.ZERO
var _hop_factor: float = 0.0

func reset() -> void:
	_air_left = 0.0
	_ground_left = FIRST_GROUND_TIME

func is_airborne() -> bool:
	return _air_left > 0.0

func desired_velocity(plant: Plant, delta: float) -> Vector2:
	if plant.ground_speed() <= 0.0: # asleep or pinned: drops to the ground
		_air_left = 0.0
		return Vector2.ZERO
	if _air_left > 0.0:
		_air_left -= delta
		if _air_left <= 1e-6:
			_air_left = 0.0
			_ground_left = GROUND_TIME
		return _hop_dir * _hop_factor
	_ground_left -= delta
	if _ground_left > 0.0:
		return Vector2.ZERO
	_start_hop(plant)
	_air_left -= delta
	return _hop_dir * _hop_factor

func hover_height(_plant: Plant) -> float:
	if _air_left <= 0.0:
		return 0.0
	return sin(PI * clampf(1.0 - _air_left / AIR_TIME, 0.0, 1.0)) * HOP_HEIGHT

## Hop length follows the plant's speed (night hour, darts). Calm: the landing point is clamped
## inside the island and out of the pond. PANIC: straight on, off the edge if it gets there.
func _start_hop(plant: Plant) -> void:
	_air_left = AIR_TIME
	var speed := plant.ground_speed()
	var from := plant.xz()
	var dir := plant.flee_direction()
	var target := from + dir * HOP_DISTANCE * speed / plant.species.base_speed
	if plant.state != Plant.State.PANIC and plant.island != null:
		target = plant.island.clamp_walkable(target, Plant.EDGE_MARGIN + HOP_EDGE_MARGIN, Plant.OBSTACLE_MARGIN)
	var v := target - from
	_hop_dir = v.normalized() if v.length_squared() > 1e-8 else Vector2.ZERO
	_hop_factor = v.length() / (AIR_TIME * speed)
