class_name BehaviorStalker
extends PlantBehavior
## Ronce-Angoisse: never flees, creeps towards the heroine.

func desired_velocity(plant: Plant, _delta: float) -> Vector2:
	if not plant.has_threat():
		return Vector2.ZERO
	return Steering.seek(plant.xz(), plant.threat_xz())
