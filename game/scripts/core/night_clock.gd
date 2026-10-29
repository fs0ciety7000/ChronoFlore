class_name NightClock
extends RefCounted
## In-game night clock: 0..480 minutes, dawn at 480.

const NIGHT_MINUTES := 480

signal dawn_reached
signal minutes_changed(minutes: int)

var minutes: int = 0

func add_minutes(amount: int) -> void:
	var before: int = minutes
	minutes = clampi(minutes + amount, 0, NIGHT_MINUTES)
	if minutes == before:
		return
	minutes_changed.emit(minutes)
	if minutes == NIGHT_MINUTES:
		dawn_reached.emit()

func progress() -> float:
	return float(minutes) / float(NIGHT_MINUTES)

func hour() -> float:
	return float(minutes) / 60.0

func is_dawn() -> bool:
	return minutes >= NIGHT_MINUTES
