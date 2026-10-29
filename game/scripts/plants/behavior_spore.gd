class_name BehaviorSpore
extends PlantBehavior
## Champi-Panique: toddles after the heroine; once she is within TRIGGER_DISTANCE (and the last
## burst is COOLDOWN seconds old) it stops and swells for SWELL_TIME over a lilac ring (the
## telegraph), then bursts into a SporeCloud of radius 2.5 m that slows her without a petal.

const SPORE_SCENE := preload("res://scenes/hazards/spore_cloud.tscn")
const TRIGGER_DISTANCE := 2.0
const SWELL_TIME := 1.0
## Between two bursts (from the start of a swelling).
const COOLDOWN := 6.0
const FIRST_COOLDOWN := 1.0

var _cooldown: float = FIRST_COOLDOWN
var _swell_left: float = 0.0

func reset() -> void:
	_swell_left = 0.0

func is_telegraphing() -> bool:
	return _swell_left > 0.0

func faces_threat() -> bool:
	return true

func desired_velocity(plant: Plant, delta: float) -> Vector2:
	if not plant.can_attack():
		_swell_left = 0.0
		return Vector2.ZERO
	_cooldown -= delta
	if _swell_left > 0.0:
		_swell_left = maxf(_swell_left - delta, 0.0)
		return Vector2.ZERO
	var threat := plant.threat_xz()
	if _cooldown <= 0.0 and plant.xz().distance_to(threat) <= TRIGGER_DISTANCE:
		_cooldown = COOLDOWN
		_swell_left = SWELL_TIME
		var base := plant.global_position if plant.is_inside_tree() else plant.position
		plant.spawn_hazard(SPORE_SCENE.instantiate() as Hazard, base, SWELL_TIME)
		plant.play_attack(SWELL_TIME)
		return Vector2.ZERO
	return Steering.seek(plant.xz(), threat)
