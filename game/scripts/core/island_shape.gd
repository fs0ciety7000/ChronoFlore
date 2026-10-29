class_name IslandShape
extends Resource
## Walkable island contour on the XZ plane (metres; Vector2.y is world Z).

@export var outline: PackedVector2Array = PackedVector2Array()

func contains(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, outline)

## Nearest point on the outline to p.
func _nearest_edge_point(p: Vector2) -> Vector2:
	var best := p
	var best_d := INF
	var n := outline.size()
	for i in n:
		var q := Geometry2D.get_closest_point_to_segment(p, outline[i], outline[(i + 1) % n])
		var d := p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best = q
	return best

func distance_to_edge(p: Vector2) -> float:
	if outline.size() < 2:
		return 0.0
	return p.distance_to(_nearest_edge_point(p))

## Unit vector pointing from the interior towards the outside, at the edge nearest to p.
func outward_normal(p: Vector2) -> Vector2:
	if outline.size() < 2:
		return Vector2.ZERO
	var q := _nearest_edge_point(p)
	var v := (q - p) if contains(p) else (p - q)
	if v.length_squared() < 1e-12:
		v = p - centroid() # exactly on the edge: fall back to away from the centre
	return v.normalized()

## p if it is inside with at least margin to the edge; else the nearest point at margin inside.
func clamp_inside(p: Vector2, margin: float) -> Vector2:
	if outline.size() < 3:
		return p
	if contains(p) and distance_to_edge(p) >= margin:
		return p
	var q := _nearest_edge_point(p)
	var result := q - outward_normal(p) * margin
	# At convex corners the diagonal step can stay closer than margin to a side: push in again.
	for i in 4:
		if contains(result) and distance_to_edge(result) >= margin - 0.0001:
			break
		var deficit := margin - distance_to_edge(result) if contains(result) else margin
		result -= outward_normal(result) * deficit
	return result

func random_point(rng: RandomNumberGenerator, margin: float) -> Vector2:
	if outline.size() < 3:
		return Vector2.ZERO
	var lo := outline[0]
	var hi := outline[0]
	for v in outline:
		lo = lo.min(v)
		hi = hi.max(v)
	for i in 200:
		var p := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
		if contains(p) and distance_to_edge(p) >= margin:
			return p
	return clamp_inside(centroid(), margin)

## Area centroid of the polygon (vertex average if degenerate).
func centroid() -> Vector2:
	var n := outline.size()
	if n == 0:
		return Vector2.ZERO
	var area2 := 0.0
	var c := Vector2.ZERO
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		var cross := a.x * b.y - b.x * a.y
		area2 += cross
		c += (a + b) * cross
	if absf(area2) < 1e-9:
		var sum := Vector2.ZERO
		for v in outline:
			sum += v
		return sum / float(n)
	return c / (3.0 * area2)
