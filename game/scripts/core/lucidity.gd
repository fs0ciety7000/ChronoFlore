class_name Lucidity
extends RefCounted
## Player's lucidity: a number of petals lost to escapes and nightmare hits,
## regrown by capture streaks.

const STREAK_FOR_REGROW := 3
const HIT_INVULNERABILITY := 1.5

signal petal_lost(petals_left: int)
signal petal_regrown(petals: int)
signal depleted

var max_petals: int
var petals: int
var streak: int = 0

var _last_hit_time: float = -INF

func _init(p_max_petals: int = 5) -> void:
	max_petals = p_max_petals
	petals = p_max_petals

## Plant escape: ignores invulnerability, resets the capture streak.
func lose_petal() -> void:
	if petals <= 0:
		return
	petals -= 1
	streak = 0
	petal_lost.emit(petals)
	if petals == 0:
		depleted.emit()

## Nightmare contact. Returns false when still invulnerable from the last accepted hit.
func take_hit(time_s: float) -> bool:
	if time_s - _last_hit_time < HIT_INVULNERABILITY:
		return false
	_last_hit_time = time_s
	lose_petal()
	return true

func register_capture() -> void:
	streak += 1
	if streak >= STREAK_FOR_REGROW:
		streak = 0
		if petals > 0 and petals < max_petals:
			petals += 1
			petal_regrown.emit(petals)

func is_empty() -> bool:
	return petals <= 0
