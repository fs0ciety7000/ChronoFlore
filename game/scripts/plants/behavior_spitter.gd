class_name BehaviorSpitter
extends PlantBehavior
## Ortie-Regret: rooted (never moves nor wanders), always faces the heroine and, every COOLDOWN
## seconds while she is within RANGE, spits a thorn in an arc to where she stands. The thorn's
## shadow announces the landing for ThornProjectile.FLIGHT_TIME seconds.

const THORN_SCENE := preload("res://scenes/hazards/thorn_projectile.tscn")
const RANGE := 7.0
const COOLDOWN := 3.0
const FIRST_COOLDOWN := 1.0

var _cooldown: float = FIRST_COOLDOWN

func wanders() -> bool:
	return false

func faces_threat() -> bool:
	return true

func desired_velocity(plant: Plant, delta: float) -> Vector2:
	if not plant.can_attack():
		return Vector2.ZERO
	_cooldown -= delta
	var from := plant.xz()
	var target := plant.threat_xz()
	if _cooldown <= 0.0 and from.distance_to(target) <= RANGE:
		_cooldown = COOLDOWN
		var base := plant.global_position if plant.is_inside_tree() else plant.position
		var thorn := THORN_SCENE.instantiate() as ThornProjectile
		plant.spawn_hazard(thorn, Vector3(target.x, base.y, target.y), ThornProjectile.FLIGHT_TIME)
		thorn.set_origin(base)
		plant.play_attack(0.25)
	return Vector2.ZERO
