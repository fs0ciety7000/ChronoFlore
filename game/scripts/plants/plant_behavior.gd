class_name PlantBehavior
extends RefCounted
## Flight style of a species. Returns the desired XZ direction scaled by a speed factor
## (0..1, above 1 for a hop); the plant multiplies it by its effective speed.

## Builds the behavior matching a species' Behavior enum.
static func for_species(species: PlantSpecies) -> PlantBehavior:
	match species.behavior:
		PlantSpecies.Behavior.ZIGZAG:
			return BehaviorZigzag.new()
		PlantSpecies.Behavior.BURROWER:
			return BehaviorBurrower.new()
		PlantSpecies.Behavior.STALKER:
			return BehaviorStalker.new()
		PlantSpecies.Behavior.SHY_APPROACH:
			return BehaviorShyApproach.new()
		PlantSpecies.Behavior.HOPPER:
			return BehaviorHopper.new()
		PlantSpecies.Behavior.POND_SEEKER:
			return BehaviorPondSeeker.new()
		PlantSpecies.Behavior.FLOATER:
			return BehaviorFloater.new()
		PlantSpecies.Behavior.CHARGER:
			return BehaviorCharger.new()
	return BehaviorDarter.new()

## Called by the plant each time it (re)enters FLEE, and when it leaves FLEE/PANIC.
func reset() -> void:
	pass

func desired_velocity(plant: Plant, _delta: float) -> Vector2:
	return plant.flee_direction()

## True when the plant should dive underground this frame (burrowers only).
func should_burrow(_plant: Plant) -> bool:
	return false

## True while out of the net's reach (mid-hop): the net misses, darts still hit.
func is_airborne() -> bool:
	return false

## True while hidden out of reach (in the pond): every tool ignores the plant.
func is_hidden() -> bool:
	return false

## Called instead of the state machine while is_hidden() (the plant does nothing else).
func tick_hidden(_plant: Plant, _delta: float) -> void:
	pass

## True while the net captures this plant without darts (like an emerging Timidelle).
func net_window(_plant: Plant) -> bool:
	return false

## Height of the model above the ground (hop arc, float, dive below the water: negative).
func hover_height(_plant: Plant) -> float:
	return 0.0

## Hostiles: true while an attack is announced on the ground (wind-up, swelling).
func is_telegraphing() -> bool:
	return false

## Croque-Colère: true while charging.
func is_charging() -> bool:
	return false

## The ground sign the behavior owns (charge lane), or null.
func telegraph_mark() -> GroundMark:
	return null

## False for a rooted hostile (Ortie-Regret): no wandering without a threat.
func wanders() -> bool:
	return true

## True when the model keeps looking at the heroine instead of its motion.
func faces_threat() -> bool:
	return false
