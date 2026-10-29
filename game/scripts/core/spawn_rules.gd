class_name SpawnRules
extends RefCounted
## Pure rules for what spawns and how fast, as a function of the night hour (0..8).

const RARITY_WEIGHTS := {
	PlantSpecies.Rarity.COMMON: 6,
	PlantSpecies.Rarity.UNCOMMON: 3,
	PlantSpecies.Rarity.RARE: 1,
}

## Gentle capturable species whose min_hour has been reached, in catalog order.
static func eligible_capturables(catalog: GameCatalog, hour: float) -> Array[PlantSpecies]:
	var result: Array[PlantSpecies] = []
	for s in catalog.species:
		if s.capturable and not s.hostile and s.min_hour <= hour:
			result.append(s)
	return result

## Hostile species (the nightmares) whose min_hour has been reached, in catalog order.
static func eligible_hostiles(catalog: GameCatalog, hour: float) -> Array[PlantSpecies]:
	var result: Array[PlantSpecies] = []
	for s in catalog.species:
		if s.hostile and s.min_hour <= hour:
			result.append(s)
	return result

static func target_population(hour: float) -> int:
	return mini(6 + int(hour / 3.0), 8)

static func nightmare_count(hour: float) -> int:
	return mini(1 + int(hour / 3.0), 3)

static func speed_multiplier(hour: float) -> float:
	return 1.0 + 0.08 * hour

## Weighted random pick by rarity; null if the list is empty.
static func pick(eligible: Array[PlantSpecies], rng: RandomNumberGenerator) -> PlantSpecies:
	if eligible.is_empty():
		return null
	var total := 0
	for s in eligible:
		total += int(RARITY_WEIGHTS[s.rarity])
	var roll := rng.randi_range(0, total - 1)
	for s in eligible:
		roll -= int(RARITY_WEIGHTS[s.rarity])
		if roll < 0:
			return s
	return eligible[eligible.size() - 1]
