extends "res://tests/test_case.gd"
## Task B3: telegraphed hazards (Hazard base, thorn, vine ring, spore cloud) and the heroine's
## immobilized / slowed states.

const HEROINE_SCENE := preload("res://scenes/heroine/heroine.tscn")
const DT := 1.0 / 60.0

var _root: Node3D

func _heroine(at: Vector2 = Vector2.ZERO) -> Heroine:
	_ensure_root()
	var h := HEROINE_SCENE.instantiate() as Heroine
	_root.add_child(h)
	await tree.process_frame
	h.lucidity = Lucidity.new(5)
	var shape := IslandShape.new()
	shape.outline = PackedVector2Array([Vector2(-20, -20), Vector2(20, -20), Vector2(20, 20), Vector2(-20, 20)])
	h.island = shape
	h.global_position = Vector3(at.x, 0.0, at.y)
	return h

func _ensure_root() -> void:
	if _root == null:
		_root = Node3D.new()
		tree.root.add_child(_root)

func _cleanup() -> void:
	if _root != null:
		_root.free()
		_root = null

func _add_hazard(hazard: Hazard, at: Vector2, telegraph: float) -> Hazard:
	_ensure_root()
	_root.add_child(hazard)
	hazard.setup(Vector3(at.x, 0.0, at.y), telegraph)
	return hazard

func _ticks(hazard: Hazard, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		if is_instance_valid(hazard) and not hazard.is_queued_for_deletion():
			hazard.tick(DT)

# --- Hazard base -------------------------------------------------------------------------------

func test_hazard_telegraph_is_at_least_0_6_s() -> void:
	var h: Hazard = _add_hazard(Hazard.new(), Vector2.ZERO, 0.2)
	assert_near(h.telegraph_time, Hazard.MIN_TELEGRAPH, 1e-6, "short telegraphs are raised to 0.6 s")
	assert_true(Hazard.MIN_TELEGRAPH >= 0.6, "minimum telegraph is 0.6 s")
	var h2: Hazard = _add_hazard(Hazard.new(), Vector2.ZERO, 1.3)
	assert_near(h2.telegraph_time, 1.3, 1e-6, "longer telegraphs are kept")
	assert_true(h.global_position.is_equal_approx(Vector3.ZERO), "placed at setup point")
	_cleanup()

func test_hazard_strikes_only_after_telegraph_and_in_radius() -> void:
	var heroine := await _heroine(Vector2(0.5, 0))
	var h: Hazard = _add_hazard(Hazard.new(), Vector2.ZERO, 0.8)
	h.radius = 1.0
	var got: Array[Node3D] = []
	h.struck.connect(func(t: Node3D) -> void: got.append(t))
	assert_true(h.is_telegraphing(), "telegraphing right after setup")
	assert_true(h.has_ground_mark(), "a ground sign is shown from the start")
	_ticks(h, 0.75)
	assert_eq(got.size(), 0, "no strike before the telegraph ends")
	_ticks(h, 0.1)
	assert_false(h.is_telegraphing(), "impact reached")
	assert_eq(got.size(), 1, "strikes the heroine inside the radius")
	if got.size() == 1:
		assert_true(got[0] == heroine, "struck target is the heroine")
	var far: Hazard = _add_hazard(Hazard.new(), Vector2(5, 0), 0.6)
	var got_far: Array[int] = [0]
	far.struck.connect(func(_t: Node3D) -> void: got_far[0] += 1)
	_ticks(far, 0.7)
	assert_eq(got_far[0], 0, "no strike outside the radius")
	_cleanup()

func test_hazard_frees_itself_after_linger() -> void:
	var h: Hazard = _add_hazard(Hazard.new(), Vector2.ZERO, 0.6)
	h.linger = 0.3
	_ticks(h, 1.0)
	assert_true(h.is_queued_for_deletion(), "freed after telegraph + linger")
	_cleanup()

# --- Heroine: immobilized, slowed --------------------------------------------------------------

func test_heroine_immobilize_keeps_longest() -> void:
	var h := await _heroine()
	assert_near(h.move_speed(), Heroine.SPEED, 1e-6, "full speed by default")
	h.immobilize(1.0)
	assert_true(h.is_immobilized(), "immobilized")
	assert_near(h.move_speed(), 0.0, 1e-6, "cannot walk while immobilized")
	h.tick_status(0.5)
	h.immobilize(0.3)
	assert_near(h.immobilized_left(), 0.5, 1e-4, "a shorter hold does not shorten nor add")
	h.immobilize(0.8)
	assert_near(h.immobilized_left(), 0.8, 1e-4, "a longer hold replaces, no stacking (not 1.3)")
	h.tick_status(0.81)
	assert_false(h.is_immobilized(), "free again")
	assert_near(h.move_speed(), Heroine.SPEED, 1e-6, "full speed again")
	_cleanup()

func test_heroine_slow_keeps_longest() -> void:
	var h := await _heroine()
	h.slow(0.5, 2.0)
	assert_true(h.is_slowed(), "slowed")
	assert_near(h.move_speed(), Heroine.SPEED * 0.5, 1e-4, "half speed")
	h.slow(0.5, 2.0)
	h.slow(0.5, 2.0)
	assert_near(h.slowed_left(), 2.0, 1e-4, "repeated slows do not add up")
	assert_near(h.move_speed(), Heroine.SPEED * 0.5, 1e-4, "factors do not multiply")
	h.tick_status(1.5)
	h.slow(0.5, 0.2)
	assert_near(h.slowed_left(), 0.5, 1e-4, "keeps the longest remaining")
	h.tick_status(0.6)
	assert_false(h.is_slowed(), "slow over")
	h.immobilize(0.5)
	h.slow(0.5, 2.0)
	assert_near(h.move_speed(), 0.0, 1e-6, "immobilized wins over slowed")
	_cleanup()

func test_immobilized_heroine_does_not_walk() -> void:
	var h := await _heroine()
	h.immobilize(1.0)
	Input.action_press("move_right")
	for i in 10:
		h._physics_process(DT)
	Input.action_release("move_right")
	assert_true(Vector2(h.global_position.x, h.global_position.z).length() < 0.01, "held in place")
	_cleanup()

# --- Vine ring ---------------------------------------------------------------------------------

func test_vine_ring_immobilizes_once_per_window() -> void:
	var h := await _heroine()
	var ring := _add_hazard(VineRing.new(), Vector2(0.4, 0.0), 1.0) as VineRing
	assert_true(ring.has_ground_mark(), "ground sign before the vines")
	_ticks(ring, 0.9)
	assert_false(h.is_immobilized(), "not held before the vines spring")
	_ticks(ring, 0.15)
	assert_true(h.is_immobilized(), "held once the vines spring")
	assert_near(h.immobilized_left(), VineRing.HOLD_TIME, 1e-4, "held 1 s")
	assert_eq(h.lucidity.petals, 4, "the vines cost one petal")
	h.tick_status(0.5)
	_ticks(ring, 0.5) # lingering vines do not hold her again
	assert_near(h.immobilized_left(), 0.5, 1e-3, "no re-hold while the vines linger")
	var again := _add_hazard(VineRing.new(), Vector2.ZERO, 0.6) as VineRing
	_ticks(again, 0.65)
	assert_eq(h.lucidity.petals, 4, "a second ring in the invulnerability window costs nothing")
	assert_near(h.immobilized_left(), 0.5, 1e-3, "nor holds her again in that window")
	var outside := _add_hazard(VineRing.new(), Vector2(3.0, 0.0), 0.6) as VineRing
	var struck: Array[int] = [0]
	outside.struck.connect(func(_t: Node3D) -> void: struck[0] += 1)
	_ticks(outside, 0.65)
	assert_eq(struck[0], 0, "a ring 3 m away misses")
	_cleanup()

# --- Spore cloud, stacking (Review Focus 2) ----------------------------------------------------

func test_spore_cloud_slows_while_inside() -> void:
	var h := await _heroine()
	var cloud := _add_hazard(SporeCloud.new(), Vector2(1.0, 0.0), 1.0) as SporeCloud
	_ticks(cloud, 1.05)
	assert_true(h.is_slowed(), "slowed in the cloud")
	assert_eq(h.lucidity.petals, 5, "no petal")
	h.global_position = Vector3(6, 0, 0)
	h.tick_status(2.1)
	_ticks(cloud, 0.5)
	assert_false(h.is_slowed(), "out of the cloud, the slow wears off")
	_cleanup()

func test_stacked_hazards_one_petal_and_no_cc_stacking() -> void:
	var h := await _heroine()
	var hits: Array[int] = [0]
	h.nightmare_hit.connect(func() -> void: hits[0] += 1)
	var all: Array[Hazard] = [
		_add_hazard(ThornProjectile.new(), Vector2(0.2, 0.0), 0.6),
		_add_hazard(VineRing.new(), Vector2(0.0, 0.3), 0.6),
		_add_hazard(SporeCloud.new(), Vector2(-0.5, 0.0), 0.6),
	]
	for i in int(0.7 / DT):
		for hz in all:
			if is_instance_valid(hz) and not hz.is_queued_for_deletion():
				hz.tick(DT)
	assert_eq(h.lucidity.petals, 4, "three hazards at once: one petal")
	assert_eq(hits[0], 1, "one accepted hit")
	assert_true(h.immobilized_left() <= VineRing.HOLD_TIME + 1e-4, "hold not stacked")
	assert_true(h.slowed_left() <= SporeCloud.SLOW_TIME + 1e-4, "slow not stacked")
	h.tick_status(0.4)
	var more: Array[Hazard] = [
		_add_hazard(VineRing.new(), Vector2.ZERO, 0.6),
		_add_hazard(ThornProjectile.new(), Vector2.ZERO, 0.6),
		_add_hazard(SporeCloud.new(), Vector2.ZERO, 0.6),
		_add_hazard(SporeCloud.new(), Vector2.ZERO, 0.6),
	]
	var held := h.immobilized_left()
	for i in int(0.65 / DT):
		for hz in more:
			if is_instance_valid(hz) and not hz.is_queued_for_deletion():
				hz.tick(DT)
	assert_eq(h.lucidity.petals, 4, "still one petal within the invulnerability window")
	assert_near(h.immobilized_left(), held, 1e-4, "no new hold within the window")
	assert_near(h.slowed_left(), SporeCloud.SLOW_TIME, 1e-4, "slow refreshed to the longest, not summed")
	assert_near(h.move_speed(), 0.0 if h.is_immobilized() else Heroine.SPEED * SporeCloud.SLOW_FACTOR, 1e-6,
		"held beats slowed, slows never multiply")
	_cleanup()
