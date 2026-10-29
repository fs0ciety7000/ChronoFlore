class_name PlantBehavior
extends RefCounted
## Flight style of a species. Returns the desired XZ direction scaled by a speed factor
## (0..1); the plant multiplies it by its effective speed.

## Builds the behavior matching a species' Behavior enum.
static func for_species(species: PlantSpecies) -> PlantBehavior:
	match species.behavior:
		PlantSpecies.Behavior.ZIGZAG:
			return BehaviorZigzag.new()
		PlantSpecies.Behavior.BURROWER:
			return BehaviorBurrower.new()
		PlantSpecies.Behavior.STALKER:
			return BehaviorStalker.new()
	return BehaviorDarter.new()

## Called by the plant each time it (re)enters FLEE.
func reset() -> void:
	pass

func desired_velocity(plant: Plant, _delta: float) -> Vector2:
	return plant.flee_direction()

## True when the plant should dive underground this frame (burrowers only).
func should_burrow(_plant: Plant) -> bool:
	return false
