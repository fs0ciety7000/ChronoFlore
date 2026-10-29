class_name BehaviorZigzag
extends PlantBehavior
## Nostalgerbe: zigzags, and freezes while out of the heroine's aim cone unless she is close.

const FLIP_TIME := 0.6
const CONE_HALF_ANGLE_DEG := 45.0
const CONE_RANGE := 30.0
const NEAR_DISTANCE := Plant.ALERT_RADIUS

var _t: float = 0.0

func reset() -> void:
	_t = 0.0

func desired_velocity(plant: Plant, delta: float) -> Vector2:
	_t += delta
	var threat := plant.threat_xz()
	var aim := plant.aim_dir()
	var near := plant.xz().distance_to(threat) < NEAR_DISTANCE
	# A zero aim means no aim information: never freeze on it.
	if not near and aim != Vector2.ZERO \
			and not Steering.in_cone(threat, aim, plant.xz(), CONE_HALF_ANGLE_DEG, CONE_RANGE):
		return Vector2.ZERO
	var phase := 1 if int(_t / FLIP_TIME) % 2 == 0 else -1
	return Steering.zigzag(plant.flee_direction(), phase)
