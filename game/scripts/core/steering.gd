class_name Steering
extends RefCounted
## Pure steering helpers on the XZ plane (Vector2.y is world Z). All results are unit vectors or zero.

## Below this distance to the edge, a calm flee bends inward.
const EDGE_AVOID_DISTANCE := 3.0
const ZIGZAG_ANGLE_DEG := 35.0

## Away from threat. Calm (panic false): near the edge the outward component is removed and an
## inward push added, so dot(result, outward_normal) <= 0. Panic: straight to the nearest edge.
static func flee(plant: Vector2, threat: Vector2, island: IslandShape, panic: bool) -> Vector2:
	if panic and island != null:
		return island.outward_normal(plant)
	var away := plant - threat
	if away.length_squared() < 1e-8:
		away = (plant - island.centroid()) if island != null else Vector2.RIGHT
		if away.length_squared() < 1e-8:
			away = Vector2.RIGHT
	away = away.normalized()
	if island == null:
		return away
	var d := island.distance_to_edge(plant)
	if island.contains(plant) and d >= EDGE_AVOID_DISTANCE:
		return away
	var n := island.outward_normal(plant)
	var tangent := away - n * maxf(away.dot(n), 0.0)
	if tangent.length() < 0.1:
		tangent = n.orthogonal() # cornered head-on: slide along the edge
	var inward := 1.0 - clampf(d / EDGE_AVOID_DISTANCE, 0.0, 1.0) if island.contains(plant) else 1.0
	return (tangent.normalized() - n * inward).normalized()

## dir rotated by +35 deg (phase_sign >= 0) or -35 deg (phase_sign < 0).
static func zigzag(dir: Vector2, phase_sign: int) -> Vector2:
	var s := 1.0 if phase_sign >= 0 else -1.0
	return dir.rotated(deg_to_rad(ZIGZAG_ANGLE_DEG) * s)

static func seek(from: Vector2, to: Vector2) -> Vector2:
	var v := to - from
	if v.length_squared() < 1e-8:
		return Vector2.ZERO
	return v.normalized()

static func in_cone(origin: Vector2, dir: Vector2, target: Vector2, half_angle_deg: float, max_range: float) -> bool:
	var to := target - origin
	var dist := to.length()
	if dist > max_range:
		return false
	if dist < 1e-6:
		return true
	if dir.length_squared() < 1e-8:
		return false
	return absf(dir.angle_to(to)) <= deg_to_rad(half_angle_deg)
