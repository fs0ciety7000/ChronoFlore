class_name PlantSpecies
extends Resource
## Static description of a plant species (an emotion), loaded from data/species/*.tres.

enum Rarity { COMMON, UNCOMMON, RARE }
## Values are stored as ints in the .tres files: only append.
enum Behavior { DARTER, ZIGZAG, BURROWER, STALKER, SHY_APPROACH, HOPPER, POND_SEEKER, FLOATER }

const REWARD_MINUTES := { Rarity.COMMON: 20, Rarity.UNCOMMON: 40, Rarity.RARE: 60 }

@export var id: StringName
@export var display_name: String
@export var emotion: String
@export var rarity: Rarity = Rarity.COMMON
@export var capturable: bool = true
@export var base_speed: float = 3.0 ## m/s
@export var min_hour: float = 0.0
@export var behavior: Behavior = Behavior.DARTER
@export var panic_after: float = 8.0 ## seconds alerted before panicking
@export var visual_scene: PackedScene ## may be null until the visuals exist
@export_multiline var fragment: String
@export var details: PackedStringArray ## exactly 2, revealed at 5 and 15 captures

## Night minutes gained by capturing this species; 0 if it cannot be captured.
func minutes_reward() -> int:
	if not capturable:
		return 0
	return REWARD_MINUTES[rarity]
