class_name AimAssist
extends RefCounted
## Pure aim helpers on the XZ plane (Vector2.y is world Z). Gameplay never reads the mouse:
## it reads a direction, optionally nudged towards the best target in a cone.

enum Source { MOUSE, STICK, MOVE, AUTO }

const STRENGTH := { Source.MOUSE: 0.3, Source.STICK: 0.7, Source.MOVE: 0.7, Source.AUTO: 1.0 }
const CONE_HALF_ANGLE := 30.0
const STICK_THRESHOLD := 0.3

## Index of the target in the cone (smallest angle, then distance), or -1.
static func best_target(origin: Vector2, dir: Vector2, targets: PackedVector2Array, max_range: float) -> int:
	if dir.length_squared() < 1e-8:
		return -1
	var best := -1
	var best_angle := INF
	var best_dist := INF
	for i in targets.size():
		var to := targets[i] - origin
		var dist := to.length()
		if dist > max_range or dist < 1e-6:
			continue
		var angle := absf(rad_to_deg(dir.angle_to(to)))
		if angle > CONE_HALF_ANGLE:
			continue
		if angle < best_angle - 1e-4 or (absf(angle - best_angle) <= 1e-4 and dist < best_dist):
			best = i
			best_angle = angle
			best_dist = dist
	return best

## dir rotated towards the best target by STRENGTH[source]; unchanged when none.
static func assisted_direction(origin: Vector2, dir: Vector2, targets: PackedVector2Array, max_range: float, source: Source) -> Vector2:
	var i := best_target(origin, dir, targets, max_range)
	if i < 0:
		return dir
	var turn := dir.angle_to(targets[i] - origin) * float(STRENGTH[source])
	return dir.rotated(turn).normalized()

## Aim source follows the last device used.
static func pick_source(current: Source, mouse_moved: bool, stick: Vector2, move: Vector2, pad_active: bool) -> Source:
	if stick.length() > STICK_THRESHOLD:
		return Source.STICK
	if mouse_moved:
		return Source.MOUSE
	# Never freeze: an idle stick falls back to the move direction, even if the pad vanished.
	if current == Source.STICK:
		return Source.MOVE
	# A pad player who only uses the left stick; keyboard+mouse players (no pad) stay on MOUSE.
	if current == Source.MOUSE and pad_active and move.length() > STICK_THRESHOLD:
		return Source.MOVE
	return current
