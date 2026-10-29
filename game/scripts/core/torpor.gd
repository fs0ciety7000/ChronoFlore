class_name Torpor
extends RefCounted
## A plant's state against the tools: tranquilizer charges (slow, then sleep) and harpoon pin.

const SLOW_PER_CHARGE := 0.25
const SLEEP_CHARGES := 3
const SLEEP_DURATION := 3.0
const DECAY_INTERVAL := 2.5
const PIN_DURATION := 3.0
const NET_MIN_CHARGES := 2

signal fell_asleep

var charges: int = 0

var _sleep_left: float = 0.0
var _pin_left: float = 0.0
var _decay_timer: float = 0.0

## +1 charge and restart decay. At SLEEP_CHARGES the plant falls asleep and charges reset.
## Does nothing while asleep.
func add_dart() -> void:
	if is_asleep():
		return
	charges += 1
	_decay_timer = 0.0
	if charges >= SLEEP_CHARGES:
		charges = 0
		_sleep_left = SLEEP_DURATION
		fell_asleep.emit()

func pin() -> void:
	_pin_left = PIN_DURATION

func tick(delta: float) -> void:
	_sleep_left = maxf(_sleep_left - delta, 0.0)
	_pin_left = maxf(_pin_left - delta, 0.0)
	if is_asleep() or charges <= 0:
		_decay_timer = 0.0
		return
	_decay_timer += delta
	while _decay_timer >= DECAY_INTERVAL and charges > 0:
		_decay_timer -= DECAY_INTERVAL
		charges -= 1
	if charges <= 0:
		_decay_timer = 0.0

func is_asleep() -> bool:
	return _sleep_left > 0.0

func is_pinned() -> bool:
	return _pin_left > 0.0

func speed_factor() -> float:
	if is_asleep() or is_pinned():
		return 0.0
	return 1.0 - SLOW_PER_CHARGE * float(charges)

func net_can_capture(emerging: bool) -> bool:
	return is_asleep() or is_pinned() or charges >= NET_MIN_CHARGES or emerging
