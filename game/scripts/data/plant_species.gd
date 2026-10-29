class_name PlantSpecies
extends Resource
## Static description of a plant species (an emotion), loaded from data/species/*.tres.

enum Rarity { COMMON, UNCOMMON, RARE }
## Values are stored as ints in the .tres files: only append.
enum Behavior { DARTER, ZIGZAG, BURROWER, STALKER, SHY_APPROACH, HOPPER, POND_SEEKER, FLOATER,
	CHARGER, ROOT_TRAP, SPITTER, SPORE }

const REWARD_MINUTES := { Rarity.COMMON: 20, Rarity.UNCOMMON: 40, Rarity.RARE: 60 }
## A hostile netted while asleep: risky but rewarding.
const HOSTILE_REWARD_MINUTES := 40

@export var id: StringName
@export var display_name: String
@export var emotion: String
@export var rarity: Rarity = Rarity.COMMON
## False only for a species the net can never take.
@export var capturable: bool = true
## Hostile ("nightmare"): never flees, attacks the heroine, spawns as a nightmare, and the net
## takes it only while it sleeps (3 darts).
@export var hostile: bool = false
@export var base_speed: float = 3.0 ## m/s
@export var min_hour: float = 0.0
@export var behavior: Behavior = Behavior.DARTER
@export var panic_after: float = 8.0 ## seconds alerted before panicking
@export var visual_scene: PackedScene ## may be null until the visuals exist
@export_multiline var fragment: String
@export var details: PackedStringArray ## exactly 2, revealed at 5 and 15 captures

## Night minutes gained by capturing this species; 0 if it cannot be captured.
## A hostile is only ever captured asleep and gives HOSTILE_REWARD_MINUTES.
func minutes_reward() -> int:
	if not capturable:
		return 0
	if hostile:
		return HOSTILE_REWARD_MINUTES
	return REWARD_MINUTES[rarity]
