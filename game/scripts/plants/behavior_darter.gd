class_name BehaviorDarter
extends PlantBehavior
## Revette: short straight sprints, then a pause to "breathe".

const SPRINT_TIME := 1.2
const PAUSE_TIME := 0.8

var _t: float = 0.0

func reset() -> void:
	_t = 0.0

func desired_velocity(plant: Plant, delta: float) -> Vector2:
	_t += delta
	if fmod(_t, SPRINT_TIME + PAUSE_TIME) >= SPRINT_TIME:
		return Vector2.ZERO
	return plant.flee_direction()
