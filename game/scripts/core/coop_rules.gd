class_name CoopRules
extends RefCounted
## Pure local co-op rules on the XZ plane (Vector2.y is world Z): balance, camera framing,
## leash and nearest player.

## Two nets empty the island faster: more gentle plants...
const POPULATION_FACTOR := 1.3
## ...and one more nightmare.
const EXTRA_NIGHTMARES := 1
## A player is held this far (metres) from the other: soft leash, never a teleport.
const LEASH_DISTANCE := 14.0
## The camera's ortho size grows up to this factor of the solo size as the players part.
const CAMERA_MAX_SCALE := 1.5

## Gentle plant target: roundi(base * 1.3) in co-op, base in solo.
static func population(base: int, coop: bool) -> int:
	return roundi(base * POPULATION_FACTOR) if coop else base

## Nightmare target: base + 1 in co-op, base in solo.
static func nightmares(base: int, coop: bool) -> int:
	return base + EXTRA_NIGHTMARES if coop else base

## Ortho size from solo_size (players together) to solo_size * 1.5 (LEASH_DISTANCE apart),
## linear in between and clamped outside.
static func camera_size(solo_size: float, spread: float) -> float:
	var t := clampf(spread / LEASH_DISTANCE, 0.0, 1.0)
	return solo_size * lerpf(1.0, CAMERA_MAX_SCALE, t)

## pos pulled back along the line to `other` so it stays within LEASH_DISTANCE of it.
static func leash(pos: Vector2, other: Vector2) -> Vector2:
	var offset := pos - other
	if offset.length() <= LEASH_DISTANCE:
		return pos
	return other + offset.normalized() * LEASH_DISTANCE

## Index of the player nearest to point (first on a tie), or -1 without players.
static func nearest(point: Vector2, players: PackedVector2Array) -> int:
	var best := -1
	var best_d := INF
	for i in players.size():
		var d := point.distance_squared_to(players[i])
		if d < best_d:
			best_d = d
			best = i
	return best
