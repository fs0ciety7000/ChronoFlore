class_name BehaviorRootTrap
extends PlantBehavior
## Lierre-Jalousie: creeps after the heroine (keeping KEEP_DISTANCE) and, every COOLDOWN seconds
## while she is within CAST_RANGE, makes a vine ring spring under her (VineRing, telegraphed
## VineRing.TELEGRAPH seconds on the ground). It stands still while casting.

const VINE_RING_SCENE := preload("res://scenes/hazards/vine_ring.tscn")
const CAST_RANGE := 7.0
const COOLDOWN := 5.0
const FIRST_COOLDOWN := 1.5
const KEEP_DISTANCE := 3.0
## Stands still this long after a cast (its Attack plays over the telegraph).
const CAST_PAUSE := 0.8

var _cooldown: float = FIRST_COOLDOWN
var _pause: float = 0.0

func faces_threat() -> bool:
	return true

func desired_velocity(plant: Plant, delta: float) -> Vector2:
	if not plant.can_attack():
		_pause = 0.0
		return Vector2.ZERO
	_cooldown -= delta
	_pause = maxf(_pause - delta, 0.0)
	var threat := plant.threat_xz()
	var dist := plant.xz().distance_to(threat)
	if _cooldown <= 0.0 and dist <= CAST_RANGE:
		_cooldown = COOLDOWN
		_pause = CAST_PAUSE
		var y := plant.global_position.y if plant.is_inside_tree() else plant.position.y
		plant.spawn_hazard(VINE_RING_SCENE.instantiate() as Hazard, Vector3(threat.x, y, threat.y), VineRing.TELEGRAPH)
		plant.play_attack(VineRing.TELEGRAPH)
	if _pause > 0.0 or dist <= KEEP_DISTANCE:
		return Vector2.ZERO
	return Steering.seek(plant.xz(), threat)
