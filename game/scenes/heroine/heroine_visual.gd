extends Node3D
## Hand-made character visual (heroine.glb by default, ~1.1 m, faces +Z) holding the current
## tool in hand.R (HandTools: Net, DartGun, Harpoon). Plays Idle/Walk by movement, Swing when a
## tool is used and Hurt + a white blink on hits. Reused by hero2_visual.tscn with another model.
## Between uses the right hand holds the net (or harpoon) over the right shoulder: the Idle and
## Walk actions key a shoulder-carry arm and the prop takes its carry transform in hand. A Swing
## (or a harpoon shot) blends the prop to its swing transform in CARRY_BLEND, then back.

const LOCOMOTION_BLEND := 0.15
## Swing blend from the carry: the arm and the prop's in-between take the same time.
const ONE_SHOT_BLEND := 0.08
const CARRY_BLEND := 0.08
## Grip point along the hand bone (wrist -> fingers), m.
const PALM_OFFSET := 0.03
## The 0.6 s Walk cycle is sped up to keep pace with the 5 m/s arcade movement.
const WALK_SPEED := 1.5
const ONE_SHOTS: Array[StringName] = [&"Swing", &"Hurt"]
const FLASH_ALPHA := 0.85
## Dart gun / harpoon shot: the prop kicks back this far (hand space, m) and settles.
const RECOIL_DISTANCE := 0.12
const RECOIL_TIME := 0.18
## Props carried on the shoulder between uses (the dart gun keeps its in-hand transform).
const CARRIED: Array[StringName] = [&"Net", &"Harpoon"]
## Shoulder carry in the visual's space (faces +Z, her right is -X): from the grip by the right
## collarbone the handle runs up and back over the right shoulder, the hoop behind the head.
const CARRY_GRIP := Vector3(-0.16, 0.50, 0.085)
const CARRY_DIR := Vector3(-0.2, 0.85, -0.5)
## After a harpoon shot the harpoon stays in hand this long before going back on the shoulder.
const SHOT_HOLD := 0.35
## Net swing trail: a narrow ribbon following the hoop's real path (emitted from the hoop centre
## every frame of the Swing), fading out over TRAIL_LIFE.
const TRAIL_LIFE := 0.22
const TRAIL_WIDTH := 0.26
const TRAIL_HEAD := Color(1.0, 1.0, 1.0, 0.9)
const TRAIL_TAIL := Color(1.0, 0.62, 0.8, 0.0)
## "Scoop" at the strike: the hoop and bag stretch then settle.
const SCOOP_AT := 0.18
const SCOOP_TIME := 0.18
## Hoop: wider in its ring plane (local XZ); bag: longer (local Y) as it scoops.
const SCOOP_HOOP := Vector3(1.25, 1.0, 1.25)
const SCOOP_BAG := Vector3(1.2, 1.45, 1.2)
## Built at runtime under the hand bone (see _attach_hand_tools).
const HAND_TOOLS_SCENE := preload("res://scenes/heroine/hand_tools.tscn")
## Hand prop shown for each tool effect; the net is the default.
const TOOL_PROPS := {
	ToolData.Effect.CAPTURE: ^"Net",
	ToolData.Effect.TORPOR: ^"DartGun",
	ToolData.Effect.PIN: ^"Harpoon",
}

## Skinned body mesh (gets the hurt flash overlay); set per model scene.
@export var body_mesh_path: NodePath = ^"Model/Heroine/Skeleton3D/HeroineMesh"
## Parent of the Net/DartGun/Harpoon props, under the hand.R BoneAttachment3D. Both nodes are
## created at runtime: Skeleton3D/<attachment>/<tools> from this path (see _attach_hand_tools).
@export var hand_tools_path: NodePath = ^"Model/Heroine/Skeleton3D/HandR/HandTools"
@export var hand_bone: StringName = &"hand.R"

var _walking: bool = false
var _flash: StandardMaterial3D
var _blink: Tween
var _recoil: Tween
var _shots: int = 0
var _shown: StringName = &"Net"
var _hand_hold_left: float = 0.0
var _carry_xf: Dictionary = {} ## prop name -> carry transform (hand space)
var _swing_xf: Dictionary = {} ## prop name -> authored (swing) transform
var _carried_now: bool = false
var _carry_blend: Tween
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_material: StandardMaterial3D
var _trail_points: Array[Vector3] = []
var _trail_ages: Array[float] = []
var _trail_emit_left: float = 0.0
var _scoop: Tween
@onready var _anim: AnimationPlayer = $Model/AnimationPlayer
@onready var _mesh: MeshInstance3D = get_node(body_mesh_path)
@onready var _hand_tools: Node3D = _attach_hand_tools()

func _ready() -> void:
	# Hurt flash: a white unshaded overlay whose alpha is tweened.
	_flash = StandardMaterial3D.new()
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash.albedo_color = Color(1, 1, 1, 0)
	_mesh.material_overlay = _flash
	_anim.animation_finished.connect(_on_animation_finished)
	_anim.play(&"Idle")
	_build_carry()
	_build_trail()
	_update_props()

func _process(delta: float) -> void:
	_hand_hold_left = maxf(_hand_hold_left - delta, 0.0)
	_update_props()
	_tick_trail(delta)

## Adds the BoneAttachment3D and the HandTools props under the model's Skeleton3D. They are not
## saved in the .tscn: nodes added inside the instanced (non-editable) .glb are dropped when the
## export re-packs the scene, which left every exported build without tools in hand.
func _attach_hand_tools() -> Node3D:
	var existing := get_node_or_null(hand_tools_path) as Node3D
	if existing != null:
		return existing
	var count := hand_tools_path.get_name_count()
	if count < 3:
		return null
	var names := PackedStringArray()
	for i in count - 2:
		names.append(hand_tools_path.get_name(i))
	var skeleton := get_node_or_null(NodePath("/".join(names))) as Skeleton3D
	if skeleton == null or skeleton.find_bone(hand_bone) < 0:
		push_warning("HeroineVisual: no %s bone for the hand tools" % hand_bone)
		return null
	var attach := BoneAttachment3D.new()
	attach.name = hand_tools_path.get_name(count - 2)
	attach.bone_name = hand_bone
	skeleton.add_child(attach)
	var tools := HAND_TOOLS_SCENE.instantiate() as Node3D
	tools.name = hand_tools_path.get_name(count - 1)
	attach.add_child(tools)
	return tools

## Top-level ribbon mesh, drawn (at zero alpha) from the first frame so its shader is compiled
## before the first swing (Web).
func _build_trail() -> void:
	_trail_mesh = ImmediateMesh.new()
	_trail_material = StandardMaterial3D.new()
	_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_material.vertex_color_use_as_albedo = true
	_trail = MeshInstance3D.new()
	_trail.name = "NetTrail"
	_trail.top_level = true
	_trail.mesh = _trail_mesh
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_trail)
	_rebuild_trail()

## Points of the current trail (world space, oldest first) — tests.
func trail_points() -> Array[Vector3]:
	return _trail_points

func _hoop() -> Node3D:
	return _hand_tools.get_node_or_null(^"Net/Hoop") as Node3D if _hand_tools != null else null

func _tick_trail(delta: float) -> void:
	if _trail == null:
		return
	for i in _trail_ages.size():
		_trail_ages[i] += delta
	while not _trail_ages.is_empty() and _trail_ages[0] > TRAIL_LIFE:
		_trail_ages.pop_front()
		_trail_points.pop_front()
	if _trail_emit_left > 0.0:
		_trail_emit_left -= delta
		var hoop := _hoop()
		if hoop != null and hoop.is_visible_in_tree():
			_trail_points.append(hoop.get_global_transform_interpolated().origin)
			_trail_ages.append(0.0)
	_rebuild_trail()

func _rebuild_trail() -> void:
	_trail_mesh.clear_surfaces()
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _trail_material)
	var n := _trail_points.size()
	if n < 2:
		# Invisible placeholder strip at the body: keeps the trail shader compiled and drawn.
		var o := global_position
		_trail_mesh.surface_set_color(Color(1, 1, 1, 0))
		for v in [Vector3(0, 0.5, 0), Vector3(0.01, 0.5, 0), Vector3(0, 0.51, 0), Vector3(0.01, 0.51, 0)]:
			_trail_mesh.surface_add_vertex(o + v)
		_trail_mesh.surface_end()
		return
	for i in n:
		var a := _trail_points[maxi(i - 1, 0)]
		var b := _trail_points[mini(i + 1, n - 1)]
		var dir := b - a
		dir.y = 0.0
		var side := Vector3(-dir.z, 0.0, dir.x)
		side = side.normalized() if side.length_squared() > 1e-8 else Vector3.RIGHT
		var life := clampf(_trail_ages[i] / TRAIL_LIFE, 0.0, 1.0)
		var half := TRAIL_WIDTH * 0.5 * (1.0 - 0.6 * life)
		var color := TRAIL_HEAD.lerp(TRAIL_TAIL, life)
		_trail_mesh.surface_set_color(color)
		_trail_mesh.surface_add_vertex(_trail_points[i] + side * half)
		_trail_mesh.surface_set_color(color)
		_trail_mesh.surface_add_vertex(_trail_points[i] - side * half)
	_trail_mesh.surface_end()

## Hoop and bag stretch at the strike, then settle (a quick "scoop").
func _play_scoop() -> void:
	if _hand_tools == null:
		return
	var parts: Array[Node3D] = []
	var peaks: Array[Vector3] = []
	for pair in [[^"Net/Hoop", SCOOP_HOOP], [^"Net/Bag", SCOOP_BAG]]:
		var part := _hand_tools.get_node_or_null(pair[0]) as Node3D
		if part != null:
			parts.append(part)
			peaks.append(pair[1])
	if _scoop != null:
		_scoop.kill()
	for part in parts:
		part.scale = Vector3.ONE
	_scoop = create_tween()
	_scoop.tween_interval(SCOOP_AT)
	_scoop.tween_method(func(k: float) -> void:
		for i in parts.size():
			parts[i].scale = Vector3.ONE.lerp(peaks[i], k), 0.0, 1.0, SCOOP_TIME * 0.35).set_ease(Tween.EASE_OUT)
	_scoop.tween_method(func(k: float) -> void:
		for i in parts.size():
			parts[i].scale = peaks[i].lerp(Vector3.ONE, k), 0.0, 1.0, SCOOP_TIME * 0.65).set_ease(Tween.EASE_IN_OUT)

## Carry pose of a prop whose handle runs along its local +Y (net, harpoon), in the visual's
## space, gripped at `grip`; the ring / tip faces up-forward so the iso camera sees it.
static func carry_transform(grip: Vector3 = CARRY_GRIP) -> Transform3D:
	var y := CARRY_DIR.normalized()
	var x := (Vector3.RIGHT - y * y.dot(Vector3.RIGHT)).normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x, y, z), grip)

## The net and harpoon stay on hand.R. Their carry transform (hand space) is solved from the
## hand's pose at the start of Idle (the right arm's shoulder carry, keyed in the .glb): grip in
## the palm, handle over the right shoulder. Their authored transform is the swing one.
func _build_carry() -> void:
	if _hand_tools == null:
		return
	var skeleton := _hand_tools.get_parent().get_parent() as Skeleton3D
	var attach := _hand_tools.get_parent() as BoneAttachment3D
	if skeleton == null or attach == null:
		return
	var bone := skeleton.find_bone(attach.bone_name)
	if bone < 0:
		return
	_anim.seek(0.0, true) # apply the Idle carry pose now
	var skel_in_visual := global_transform.affine_inverse() * skeleton.global_transform
	var hand := skel_in_visual * skeleton.get_bone_global_pose(bone)
	var grip := hand * (Vector3.UP * PALM_OFFSET)
	var local := hand.affine_inverse() * carry_transform(grip)
	for prop_name in CARRIED:
		var prop := _hand_tools.get_node_or_null(NodePath(prop_name)) as Node3D
		if prop == null:
			continue
		_swing_xf[prop_name] = prop.transform
		_carry_xf[prop_name] = local
		prop.transform = local
	_carried_now = true

## True while the shown prop rests on the shoulder (no swing, no harpoon shot under way).
func is_carrying() -> bool:
	return not _carry_xf.is_empty() and _shown in CARRIED and _hand_hold_left <= 0.0 \
			and not (_anim.is_playing() and _anim.current_animation == &"Swing")

## The carried prop ("Net", "Harpoon") in hand.R, or null.
func carried_prop(prop_name: StringName) -> Node3D:
	return _hand_tools.get_node_or_null(NodePath(prop_name)) as Node3D if _carry_xf.has(prop_name) else null

## Carry (hand space) and swing transforms of a carried prop (tests).
func carry_local(prop_name: StringName) -> Transform3D:
	return _carry_xf.get(prop_name, Transform3D())

func swing_local(prop_name: StringName) -> Transform3D:
	return _swing_xf.get(prop_name, Transform3D())

func _update_props() -> void:
	if _hand_tools == null:
		return
	for prop in _hand_tools.get_children():
		(prop as Node3D).visible = StringName(prop.name) == _shown
	var carrying := is_carrying()
	if carrying != _carried_now and not _carry_xf.is_empty():
		_carried_now = carrying
		_blend_props(_carry_xf if carrying else _swing_xf)

## Short in-between (CARRY_BLEND) from the props' current transforms to `target`.
func _blend_props(target: Dictionary) -> void:
	if _carry_blend != null:
		_carry_blend.kill()
	var from := {}
	for prop_name in target:
		from[prop_name] = (_hand_tools.get_node(NodePath(prop_name)) as Node3D).transform
	_carry_blend = create_tween()
	_carry_blend.tween_method(func(t: float) -> void:
		for prop_name in target:
			var a: Transform3D = from[prop_name]
			(_hand_tools.get_node(NodePath(prop_name)) as Node3D).transform = a.interpolate_with(target[prop_name], t),
		0.0, 1.0, CARRY_BLEND)

func animation_player() -> AnimationPlayer:
	return _anim

func set_walking(on: bool) -> void:
	if on == _walking:
		return
	_walking = on
	if not _is_one_shot_playing():
		_play_locomotion()

## Shows the prop of `tool` in hand (wired to ToolBelt.tool_changed by Heroine); null = net.
func set_tool(tool: ToolData) -> void:
	if _hand_tools == null:
		return
	var shown: NodePath = TOOL_PROPS[tool.effect] if tool != null else ^"Net"
	_shown = StringName(str(shown))
	_hand_hold_left = 0.0
	_update_props()

## Name of the current tool's prop, in hand or on the shoulder ("" if none).
func shown_tool_prop() -> String:
	return String(_shown) if _hand_tools != null else ""

## Net/tool swing (wired to ToolBelt.tool_used by Heroine): off the shoulder into the sweep.
func play_swing() -> void:
	_play_one_shot(&"Swing")
	_update_props()
	if _shown == &"Net":
		_trail_emit_left = _anim.get_animation(&"Swing").length
		_play_scoop()

## Dart gun / harpoon shot: a short recoil of the hand prop instead of the net swing.
func play_shot() -> void:
	_shots += 1
	if _hand_tools == null:
		return
	_hand_hold_left = SHOT_HOLD
	_update_props()
	if _recoil != null:
		_recoil.kill()
	_hand_tools.position = Vector3.ZERO
	_recoil = create_tween()
	_recoil.tween_property(_hand_tools, "position", Vector3(0.0, -RECOIL_DISTANCE, 0.0), RECOIL_TIME * 0.3)
	_recoil.tween_property(_hand_tools, "position", Vector3.ZERO, RECOIL_TIME * 0.7).set_ease(Tween.EASE_OUT)

## Shots played so far (tests).
func shot_count() -> int:
	return _shots

## Quick flinch and white flash while invulnerable.
func blink_hurt() -> void:
	_play_one_shot(&"Hurt")
	if _blink != null:
		_blink.kill()
	_blink = create_tween().set_loops(3)
	_blink.tween_method(_set_flash, 0.0, 1.0, 0.08)
	_blink.tween_method(_set_flash, 1.0, 0.0, 0.08)

func _play_one_shot(anim_name: StringName) -> void:
	if _anim.current_animation == anim_name:
		_anim.seek(0.0, true) # restart instead of ignoring a repeated trigger
	else:
		_anim.play(anim_name, ONE_SHOT_BLEND)

func _play_locomotion() -> void:
	if _walking:
		_anim.play(&"Walk", LOCOMOTION_BLEND, WALK_SPEED)
	else:
		_anim.play(&"Idle", LOCOMOTION_BLEND)

func _is_one_shot_playing() -> bool:
	return _anim.is_playing() and StringName(_anim.current_animation) in ONE_SHOTS

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name in ONE_SHOTS:
		_play_locomotion()
	_update_props()

func _set_flash(v: float) -> void:
	_flash.albedo_color.a = v * FLASH_ALPHA
