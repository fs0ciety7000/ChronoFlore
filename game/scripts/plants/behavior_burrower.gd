class_name BehaviorBurrower
extends PlantBehavior
## Timidelle: flees, and burrows when the heroine comes close (the plant runs the burrow cycle).

const BURROW_TRIGGER_DISTANCE := Plant.ALERT_RADIUS

func should_burrow(plant: Plant) -> bool:
	return plant.has_threat() and plant.xz().distance_to(plant.threat_xz()) < BURROW_TRIGGER_DISTANCE
