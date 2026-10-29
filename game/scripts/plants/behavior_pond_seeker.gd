class_name BehaviorPondSeeker
extends PlantBehavior
## Mélancolys: walks slowly to the pond and dives in, out of reach of every tool, then drifts
## away from the heroine as a floating lily and comes out on the far shore. Intercept it before.
## Shore targets are points on the pond's walkable ring that it can walk to in a straight line
## without crossing the water or passing near the heroine; it never steps into the water.

const HIDE_DURATION := 4.0
## Within this of its shore target it dives.
const DIVE_DISTANCE := 0.3
## Shore targets (and the straight way to them) keep this distance to the heroine.
const HEROINE_CLEARANCE := 1.3
## Comes out at least this far from the heroine (when the shore allows it).
const EMERGE_CLEARANCE := 2.5
## The hidden lily floats this far inside the water's edge...
const LILY_INSET := 1.0
## ...and drifts away from the heroine this fast (m/s).
const DRIFT_SPEED := 0.5
## Shore points tried around the pond.
const SHORE_SAMPLES := 24
## After coming out it flees normally this long before heading for the water again.
const EMERGE_REST := 2.5
## Model sinks this deep while hidden: only the lily crown floats on the water.
const HIDDEN_SINK := 0.26

var _hidden_left: float = 0.0
var _rest_left: float = 0.0
var _target: Vector2 = Vector2.ZERO
var _has_target: bool = false
var _pond: Vector3 = Vector3.ZERO

## Keeps the hide going: a state change never strands it in the water.
func reset() -> void:
	_has_target = false

func is_hidden() -> bool:
	return _hidden_left > 0.0

func hover_height(_plant: Plant) -> float:
	return -HIDDEN_SINK if is_hidden() else 0.0

func desired_velocity(plant: Plant, delta: float) -> Vector2:
	if plant.state == Plant.State.PANIC or plant.island == null or not plant.has_threat():
		return plant.flee_direction()
	if _rest_left > 0.0:
		_rest_left -= delta
		return plant.flee_direction()
	var waters := plant.island.water_zones()
	if waters.is_empty():
		return plant.flee_direction()
	var pos := plant.xz()
	if not (_has_target and _valid_target(plant, _pond, _target)):
		_has_target = _pick_target(plant, waters)
	if not _has_target:
		return plant.flee_direction() # the heroine blocks the way: step away and look again
	if pos.distance_to(_target) <= DIVE_DISTANCE:
		_dive(plant)
		return Vector2.ZERO
	return Steering.seek(pos, _target)

func tick_hidden(plant: Plant, delta: float) -> void:
	_hidden_left -= delta
	var c := Vector2(_pond.x, _pond.y)
	var lily_r := maxf(_pond.z - LILY_INSET, 0.0)
	var pos := plant.xz()
	if plant.has_threat():
		var away := c - plant.threat_xz()
		if away.length_squared() > 1e-8:
			var goal := c + away.normalized() * lily_r
			pos = pos.move_toward(goal, DRIFT_SPEED * delta)
			if pos.distance_to(c) > lily_r:
				pos = c + (pos - c).normalized() * lily_r
	if _hidden_left > 1e-6:
		plant.place_xz(pos)
		return
	_hidden_left = 0.0
	plant.teleport_xz(_emerge_point(plant, pos))
	_rest_left = EMERGE_REST
	_has_target = false

## Nearest reachable shore point over every water zone.
func _pick_target(plant: Plant, waters: PackedVector3Array) -> bool:
	var pos := plant.xz()
	var best_d := INF
	for w in waters:
		for i in SHORE_SAMPLES:
			var p := _shore_point(w, TAU * float(i) / float(SHORE_SAMPLES))
			if not _valid_target(plant, w, p):
				continue
			var d := pos.distance_to(p)
			if d < best_d:
				best_d = d
				_target = p
				_pond = w
	return best_d < INF

func _shore_point(w: Vector3, angle: float) -> Vector2:
	return Vector2(w.x, w.y) + Vector2.from_angle(angle) * (w.z + Plant.OBSTACLE_MARGIN)

## On the island, and a straight walk from here that stays dry and clear of the heroine.
func _valid_target(plant: Plant, w: Vector3, p: Vector2) -> bool:
	var island := plant.island
	if not island.contains(p) or island.distance_to_edge(p) < Plant.EDGE_MARGIN:
		return false
	var pos := plant.xz()
	var threat := plant.threat_xz()
	if Geometry2D.get_closest_point_to_segment(threat, pos, p).distance_to(threat) < HEROINE_CLEARANCE:
		return false
	var c := Vector2(w.x, w.y)
	var ring := w.z + Plant.OBSTACLE_MARGIN
	return Geometry2D.get_closest_point_to_segment(c, pos, p).distance_to(c) >= ring - 0.05

func _dive(plant: Plant) -> void:
	_hidden_left = HIDE_DURATION
	_has_target = false
	var c := Vector2(_pond.x, _pond.y)
	var out := plant.xz() - c
	out = out.normalized() if out.length_squared() > 1e-8 else Vector2.RIGHT
	plant.teleport_xz(c + out * maxf(_pond.z - LILY_INSET, 0.0))

## Shore point nearest the lily that is walkable and far enough from the heroine; else the
## walkable one farthest from her.
func _emerge_point(plant: Plant, lily: Vector2) -> Vector2:
	var island := plant.island
	var threat := plant.threat_xz() if plant.has_threat() else Vector2(INF, INF)
	var best := Vector2.ZERO
	var best_d := INF
	var far := Vector2.ZERO
	var far_d := -1.0
	for i in SHORE_SAMPLES:
		var p := _shore_point(_pond, TAU * float(i) / float(SHORE_SAMPLES))
		if not island.contains(p) or island.distance_to_edge(p) < Plant.EDGE_MARGIN:
			continue
		var gap := p.distance_to(threat)
		if gap > far_d:
			far_d = gap
			far = p
		if gap >= EMERGE_CLEARANCE and p.distance_to(lily) < best_d:
			best_d = p.distance_to(lily)
			best = p
	var result := best if best_d < INF else far
	if far_d < 0.0: # no walkable shore at all: fall back to any walkable point
		result = island.clamp_walkable(lily, Plant.EDGE_MARGIN, Plant.OBSTACLE_MARGIN)
	return result
