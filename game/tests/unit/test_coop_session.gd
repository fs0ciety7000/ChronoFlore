extends "res://tests/test_case.gd"
## Task C3: local co-op night (shared lucidity, nearest-player targeting, leash, camera, HUD,
## device fallback, co-op population).

const NIGHT_SCENE := "res://scenes/night/night.tscn"
const PATH := "user://test_coop.json"
const DT := 1.0 / 60.0

var _saved_path: String
var _saved_herbarium: Herbarium
var _saved_mode: GameState.Mode

func _session(mode: GameState.Mode = GameState.Mode.COOP) -> NightSession:
	_saved_path = GameState.save_path
	_saved_herbarium = GameState.herbarium
	_saved_mode = GameState.mode
	GameState.save_path = PATH
	GameState.herbarium = Herbarium.new()
	GameState.mode = mode
	var s := (load(NIGHT_SCENE) as PackedScene).instantiate() as NightSession
	s.auto_change_scene = false
	tree.root.add_child(s)
	await tree.process_frame
	return s

func _end(s: NightSession) -> void:
	s.free()
	for p in [PATH, PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	GameState.save_path = _saved_path
	GameState.herbarium = _saved_herbarium
	GameState.mode = _saved_mode

func _xz(n: Node3D) -> Vector2:
	return Vector2(n.global_position.x, n.global_position.z)

func _place(n: Node3D, p: Vector2) -> void:
	n.global_position = Vector3(p.x, 0.0, p.y)

func _pads(ids: Array) -> Array[int]:
	var out: Array[int] = []
	for i in ids:
		out.append(int(i))
	return out

## Two walkable points `gap` metres apart across the island centre.
func _apart(s: NightSession, gap: float) -> Array[Vector2]:
	var c := s.island.shape.centroid()
	var d := Heroine.SCREEN_RIGHT.normalized() * gap * 0.5
	return [c - d, c + d]

# --- lucidity (Review Focus 2) -----------------------------------------------------------------

func test_lucidity_per_player_invulnerability() -> void:
	var l := Lucidity.new()
	assert_true(l.take_hit_for(0, 10.0), "P1 hit")
	assert_true(l.take_hit_for(1, 10.0), "P2 hit, same instant: own window")
	assert_false(l.take_hit_for(0, 10.0), "P1 again: invulnerable")
	assert_false(l.take_hit_for(1, 11.4), "P2 within 1.5 s")
	assert_eq(l.petals, 3, "two petals lost, never more")
	assert_true(l.take_hit_for(1, 11.6), "P2 after 1.5 s")
	assert_true(l.take_hit(20.0), "take_hit is P1's window")
	assert_false(l.take_hit_for(0, 20.5), "same window as index 0")

func test_shared_lucidity_two_hits() -> void:
	var s: NightSession = await _session()
	var p1 := s.players[0]
	var p2 := s.players[1]
	assert_true(p1.lucidity == p2.lucidity and p1.lucidity == s.lucidity, "one shared lucidity")
	assert_true(p1.take_nightmare_hit(), "P1 hit")
	assert_true(p2.take_nightmare_hit(), "P2 hit in the same frame")
	assert_false(p1.take_nightmare_hit(), "P1 hit twice: invulnerable")
	assert_false(p2.take_nightmare_hit(), "P2 hit twice: invulnerable")
	assert_eq(s.lucidity.petals, 3, "2 petals lost, never more")
	_end(s)

## M3: the invulnerability window runs on the session's physics time, not the wall clock.
func test_invulnerability_uses_session_time() -> void:
	var s: NightSession = await _session()
	var p1 := s.players[0]
	assert_near(p1.game_time(), s.physics_time, 1e-9, "player reads the session's physics time")
	assert_true(p1.take_nightmare_hit(), "first hit")
	OS.delay_msec(50)
	s.physics_time += Lucidity.HIT_INVULNERABILITY - 0.1
	assert_false(p1.take_nightmare_hit(), "still invulnerable after 1.4 s of play")
	s.physics_time += 0.2
	assert_true(p1.take_nightmare_hit(), "hit again after 1.6 s of play")
	_end(s)

func test_vine_ring_catches_both_players() -> void:
	var s: NightSession = await _session()
	var c := s.island.shape.centroid()
	_place(s.players[0], c + Vector2(0.4, 0))
	_place(s.players[1], c - Vector2(0.4, 0))
	var ring := (load("res://scenes/hazards/vine_ring.tscn") as PackedScene).instantiate() as VineRing
	s.plants_root.add_child(ring)
	ring.setup(Vector3(c.x, 0, c.y), VineRing.TELEGRAPH)
	var struck: Array[Node3D] = []
	ring.struck.connect(func(t: Node3D) -> void: struck.append(t))
	ring.tick(VineRing.TELEGRAPH + 0.01)
	assert_eq(struck.size(), 2, "both players struck")
	assert_true(s.players[0].is_immobilized() and s.players[1].is_immobilized(), "both held")
	assert_eq(s.lucidity.petals, 3, "one petal each")
	_end(s)

func test_spore_cloud_slows_both_players() -> void:
	var s: NightSession = await _session()
	var c := s.island.shape.centroid()
	_place(s.players[0], c + Vector2(1.0, 0))
	_place(s.players[1], c - Vector2(1.0, 0))
	var cloud := (load("res://scenes/hazards/spore_cloud.tscn") as PackedScene).instantiate() as SporeCloud
	s.plants_root.add_child(cloud)
	cloud.setup(Vector3(c.x, 0, c.y), Hazard.MIN_TELEGRAPH)
	cloud.tick(Hazard.MIN_TELEGRAPH + 0.01)
	assert_true(s.players[0].is_slowed() and s.players[1].is_slowed(), "both slowed")
	assert_eq(s.lucidity.petals, 5, "spores never cost a petal")
	_end(s)

# --- captures (Review Focus 3) -----------------------------------------------------------------

func test_double_net_single_capture() -> void:
	var s: NightSession = await _session()
	var ronce := GameState.catalog.species_by_id(&"ronce_angoisse")
	var plant := s.add_plant(ronce, s.island.shape.centroid())
	for i in Torpor.SLEEP_CHARGES:
		plant.hit_by_tool(ToolData.Effect.TORPOR)
	var captured: Array[Plant] = []
	plant.captured.connect(func(p: Plant) -> void: captured.append(p))
	var first := plant.hit_by_tool(ToolData.Effect.CAPTURE) # P1's net
	var second := plant.hit_by_tool(ToolData.Effect.CAPTURE) # P2's net, same frame
	assert_true(first, "first net captures")
	assert_false(second, "second net: already captured")
	assert_eq(captured.size(), 1, "one capture")
	assert_eq(s.clock.minutes, 40, "minutes added once")
	assert_eq(s.captures.size(), 1, "one herbarium entry")
	_end(s)

# --- devices (Review Focus 1) ------------------------------------------------------------------

func test_pad_unplug_falls_back() -> void:
	var s: NightSession = await _session()
	var p1 := s.players[0]
	var p2 := s.players[1]
	s.apply_devices(_pads([0, 1]))
	assert_eq(int(s.assignments[0]["kind"]), DeviceAssignment.Kind.PAD, "P1 on pad 0")
	assert_false(p1.auto_aim, "P1 aims with its stick")
	p1.update_aim(false, null, Vector2(0.9, 0), Vector2.ZERO, true)
	assert_eq(p1.aim_source, AimAssist.Source.STICK, "stick aim")
	s.apply_devices(_pads([1])) # pad 0 unplugged mid-night
	assert_eq(int(s.assignments[0]["kind"]), DeviceAssignment.Kind.KEYBOARD_LEFT, "P1 on its keyboard half")
	assert_eq(int(s.assignments[1]["kind"]), DeviceAssignment.Kind.PAD, "P2 keeps pad 1")
	assert_true(p1.auto_aim, "P1 aims AUTO")
	assert_false(p1.uses_mouse, "no mouse on the keyboard half")
	var before := p1.aim_dir
	p1.update_aim(false, null, Vector2.ZERO, Vector2(-1, 0), false)
	assert_eq(p1.aim_source, AimAssist.Source.AUTO, "AUTO aim")
	assert_true(p1.aim_dir.distance_to(before) > 0.1, "aim follows the keyboard walk: never frozen")
	var w := InputEventKey.new()
	w.physical_keycode = KEY_W
	assert_true(InputMap.event_is_action(w, &"p1_move_up"), "W moves P1")
	s.apply_devices(_pads([]))
	assert_eq(int(s.assignments[1]["kind"]), DeviceAssignment.Kind.KEYBOARD_RIGHT, "P2 on the arrows")
	assert_true(p2.auto_aim, "P2 aims AUTO")
	_end(s)
	assert_true(InputMap.event_is_action(w, &"p1_move_up"), "bindings restored after the night")
	var up := InputEventKey.new()
	up.physical_keycode = KEY_UP
	assert_true(InputMap.event_is_action(up, &"p1_move_up"), "solo arrows back for P1")

func test_auto_aim_then_stick_never_freezes() -> void:
	var s: NightSession = await _session()
	var p1 := s.players[0]
	s.apply_devices(_pads([]))
	p1.update_aim(false, null, Vector2.ZERO, Vector2(1, 0), false)
	s.apply_devices(_pads([0, 1]))
	assert_false(p1.auto_aim, "pad back: no more AUTO")
	var before := p1.aim_dir
	p1.update_aim(false, null, Vector2.ZERO, Vector2(0, 1), true)
	assert_true(p1.aim_dir.distance_to(before) > 0.1, "walking still turns the aim")
	_end(s)

# --- leash and camera (Review Focus 4) ---------------------------------------------------------

func test_leash_and_camera_frame_both() -> void:
	var s: NightSession = await _session()
	var p1 := s.players[0]
	var p2 := s.players[1]
	var spots := _apart(s, 10.0)
	_place(p1, spots[0])
	_place(p2, spots[1])
	s.apply_leash()
	assert_near(_xz(p1).distance_to(_xz(p2)), 10.0, 1e-3, "within the leash: free")
	# P2 walks away beyond 14 m: P2 is held, P1 is not dragged.
	var away := spots[1] + (spots[1] - spots[0]).normalized() * 6.0
	_place(p2, away)
	s.apply_leash()
	assert_near(_xz(p1).distance_to(_xz(p2)), CoopRules.LEASH_DISTANCE, 1e-3, "held at 14 m")
	assert_near(_xz(p1).distance_to(spots[0]), 0.0, 1e-3, "P1 not dragged")
	# Camera: barycentre and wider ortho size; both inside the frustum.
	s.camera.snap_to_target()
	var mid := (_xz(p1) + _xz(p2)) * 0.5
	var f := s.camera.focus_point()
	assert_near(Vector2(f.x, f.z).distance_to(mid), 0.0, 1e-3, "camera on the barycentre")
	assert_near(s.camera.ortho_size(), IsoCamera.ORTHO_SIZE * CoopRules.CAMERA_MAX_SCALE, 1e-3, "widest framing at the leash")
	var cam := s.camera.get_node("Camera3D") as Camera3D
	for p in [p1, p2]:
		assert_true(cam.is_position_in_frustum(p.global_position), "%s at the ground in frame" % p.name)
		assert_true(cam.is_position_in_frustum(p.global_position + Vector3.UP * 1.6), "%s head in frame" % p.name)
	# Together again: solo framing.
	_place(p2, spots[0] + Vector2(0.5, 0))
	s.camera.snap_to_target()
	assert_near(s.camera.ortho_size(), CoopRules.camera_size(IsoCamera.ORTHO_SIZE, 0.5), 1e-3, "close: near solo size")
	_end(s)

func test_solo_camera_unchanged() -> void:
	var s: NightSession = await _session(GameState.Mode.SOLO_HEROINE)
	s.camera.snap_to_target()
	assert_near(s.camera.ortho_size(), IsoCamera.ORTHO_SIZE, 1e-6, "solo size")
	var f := s.camera.focus_point()
	assert_near(Vector2(f.x, f.z).distance_to(_xz(s.heroine)), 0.0, 1e-3, "follows the heroine")
	_end(s)

# --- plants target the nearest player ----------------------------------------------------------

func test_plants_threat_from_nearest_player() -> void:
	var s: NightSession = await _session()
	var p1 := s.players[0]
	var p2 := s.players[1]
	var spots := _apart(s, 12.0)
	_place(p1, spots[0])
	_place(p2, spots[1])
	p2.aim_dir = Vector2(0, -1)
	var rev := s.add_plant(GameState.catalog.species_by_id(&"revette"), spots[1] + Vector2(1.5, 0))
	s.feed_threats()
	assert_near(rev.threat_xz().distance_to(spots[1]), 0.0, 1e-4, "threat = P2, the nearest")
	assert_eq(rev.aim_dir(), Vector2(0, -1), "with P2's aim")
	_end(s)

func test_ronce_hits_the_nearest_player() -> void:
	var s: NightSession = await _session()
	var p1 := s.players[0]
	var p2 := s.players[1]
	var spots := _apart(s, 12.0)
	_place(p1, spots[0])
	_place(p2, spots[1])
	var ronce := s.add_plant(GameState.catalog.species_by_id(&"ronce_angoisse"), spots[1] + Vector2(0.5, 0))
	s.feed_threats()
	ronce.step(DT)
	assert_eq(s.lucidity.petals, 4, "contact costs a petal")
	assert_true(p2.is_knocked_back(), "P2 (the nearest) took the hit")
	assert_false(p1.is_knocked_back(), "P1 untouched")
	_end(s)

## I2: contact tests every player, not only the threat (the nearest): a charge locked on P1
## still hits P2 standing in its lane.
func test_charge_hits_the_other_player_in_its_lane() -> void:
	var s: NightSession = await _session()
	var p1 := s.players[0]
	var p2 := s.players[1]
	var c := s.island.shape.centroid()
	_place(p1, c + Vector2(4.0, 0.0))
	_place(p2, c + Vector2(-6.0, 0.0))
	var croque := s.add_plant(GameState.catalog.species_by_id(&"croque_colere"), c)
	var frames := 0
	while croque.find_child("ChargeLane*", false, false) == null and frames < 300:
		croque.set_threat(_xz(p1), p1.aim_dir)
		croque.step(DT)
		frames += 1
	assert_true(croque.find_child("ChargeLane*", false, false) != null, "winds up towards P1")
	_place(p1, c + Vector2(1.0, 3.0)) # P1 side-steps; P2 walks into the locked lane
	_place(p2, c + Vector2(2.5, 0.0))
	for i in 120:
		if p2.is_knocked_back():
			break
		croque.set_threat(_xz(p1), p1.aim_dir)
		croque.step(DT)
	assert_true(p2.is_knocked_back(), "the charge hits P2 in its lane")
	assert_false(p1.is_knocked_back(), "P1 (the threat, out of the lane) untouched")
	assert_eq(s.lucidity.petals, 4, "one petal")
	assert_true(croque.is_stunned(), "croque stunned after the hit")
	_end(s)

func test_contact_hits_both_players_in_reach() -> void:
	var s: NightSession = await _session()
	var p1 := s.players[0]
	var p2 := s.players[1]
	var c := s.island.shape.centroid()
	_place(p1, c + Vector2(0.5, 0.0))
	_place(p2, c + Vector2(-0.5, 0.0))
	var ronce := s.add_plant(GameState.catalog.species_by_id(&"ronce_angoisse"), c)
	ronce.set_threat(_xz(p1), p1.aim_dir)
	ronce.step(DT)
	assert_true(p1.is_knocked_back() and p2.is_knocked_back(), "both players hit")
	assert_eq(s.lucidity.petals, 3, "one petal each, own invulnerability windows")
	_place(p1, c + Vector2(0.5, 0.0))
	ronce.step(DT)
	assert_eq(s.lucidity.petals, 3, "both still invulnerable")
	_end(s)

func test_spawn_far_from_every_player() -> void:
	var s: NightSession = await _session()
	var spots := _apart(s, 12.0)
	_place(s.players[0], spots[0])
	_place(s.players[1], spots[1])
	for i in 40:
		var p := s.spawn_point()
		assert_true(p.distance_to(spots[0]) >= NightSession.SPAWN_MIN_DISTANCE, "far from P1")
		assert_true(p.distance_to(spots[1]) >= NightSession.SPAWN_MIN_DISTANCE, "far from P2")
	_end(s)

# --- population --------------------------------------------------------------------------------

func _count(s: NightSession, hostile: bool) -> int:
	var n := 0
	for p in s.live_plants():
		if p.species.hostile == hostile:
			n += 1
	return n

func test_coop_population() -> void:
	var s: NightSession = await _session()
	assert_true(s.is_coop(), "co-op night")
	assert_eq(_count(s, false), CoopRules.population(SpawnRules.target_population(0.0), true), "8 gentle plants at 0 h")
	assert_eq(_count(s, true), SpawnRules.nightmare_count(0.0) + 1, "one more nightmare at 0 h")
	_end(s)
	var solo: NightSession = await _session(GameState.Mode.SOLO_HEROINE)
	assert_false(solo.is_coop(), "solo night")
	assert_eq(_count(solo, false), SpawnRules.target_population(0.0), "solo population")
	assert_eq(_count(solo, true), SpawnRules.nightmare_count(0.0), "solo nightmares")
	_end(solo)

# --- HUD ---------------------------------------------------------------------------------------

func test_hud_one_tool_cartouche_per_player() -> void:
	var s: NightSession = await _session()
	assert_true(s.hud.tool_panel.visible, "P1 cartouche")
	assert_true(s.hud.tool_panel_2.visible, "P2 cartouche in co-op")
	assert_true(s.hud.tool_panel_2.get_global_rect().position.x > s.hud.tool_panel.get_global_rect().end.x, "P2 on the right")
	var belt2 := s.players[1].get_node("ToolBelt") as ToolBelt
	var tools: Array[ToolData] = [GameState.catalog.tool_by_id(&"net"), GameState.catalog.tool_by_id(&"tranquilizer")]
	belt2.set_tools(tools)
	belt2.select(1)
	assert_eq(s.hud.tool_label_2.text, belt2.current().display_name, "P2 cartouche follows P2's belt")
	assert_eq(s.hud.tool_label.text, (s.players[0].get_node("ToolBelt") as ToolBelt).current().display_name, "P1 cartouche unchanged")
	_end(s)
	var solo: NightSession = await _session(GameState.Mode.SOLO_HEROINE)
	assert_false(solo.hud.tool_panel_2.visible, "no P2 cartouche in solo")
	_end(solo)
