class_name BehaviorFloater
extends PlantBehavior
## Lumiole: a glowing bulb floating at net height, very fast, weaving as it flees.

## Model height above the ground: the net still reaches it.
const FLOAT_HEIGHT := 0.8
## Asleep, it sinks closer to the grass.
const SLEEP_HEIGHT := 0.3
## Weave: the flight direction swings this much either side.
const WEAVE_ANGLE_DEG := 25.0
const WEAVE_FREQ := 1.6 ## Hz

var _t: float = 0.0

func reset() -> void:
	_t = 0.0

func desired_velocity(plant: Plant, delta: float) -> Vector2:
	_t += delta
	var dir := plant.flee_direction()
	if plant.state == Plant.State.PANIC:
		return dir
	return dir.rotated(deg_to_rad(WEAVE_ANGLE_DEG) * sin(TAU * WEAVE_FREQ * _t))

func hover_height(plant: Plant) -> float:
	return SLEEP_HEIGHT if plant.torpor.is_asleep() else FLOAT_HEIGHT
