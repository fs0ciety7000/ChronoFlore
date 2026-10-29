extends Node3D
## Hand-made character visual (heroine.glb by default, ~1.1 m, faces +Z) holding the current
## tool in hand.R (HandTools: Net, DartGun, Harpoon). Plays Idle/Walk by movement, Swing when a
## tool is used and Hurt + a white blink on hits. Reused by hero2_visual.tscn with another model.
## Between uses the net and the harpoon rest on the right shoulder (copies under a chest
## BoneAttachment3D "Carry", so they bob with the walk); a Swing or a harpoon shot takes the
## hand prop off the shoulder for the move, then it goes back. The dart gun stays lowered in hand.

const LOCOMOTION_BLEND := 0.15
const ONE_SHOT_BLEND := 0.05
## The 0.6 s Walk cycle is sped up to keep pace with the 5 m/s arcade movement.
const WALK_SPEED := 1.5
const ONE_SHOTS: Array[StringName] = [&"Swing", &"Hurt"]
const FLASH_ALPHA := 0.85
## Dart gun / harpoon shot: the prop kicks back this far (hand space, m) and settles.
const RECOIL_DISTANCE := 0.12
const RECOIL_TIME := 0.18
## Props carried on the shoulder between uses (the dart gun stays in hand).
const CARRIED: Array[StringName] = [&"Net", &"Harpoon"]
const CARRY_BONE := "chest"
## Shoulder carry in the visual's space (faces +Z, her right is -X): the handle starts by the
## right hand, rests diagonally over the right shoulder, the hoop up behind the head.
const CARRY_GRIP := Vector3(-0.18, 0.30, 0.12)
const CARRY_DIR := Vector3(-0.12, 0.85, -0.5)
## After a harpoon shot the harpoon stays in hand this long before going back on the shoulder.
const SHOT_HOLD := 0.35
## Hand prop shown for each tool effect; the net is the default.
const TOOL_PROPS := {
	ToolData.Effect.CAPTURE: ^"Net",
	ToolData.Effect.TORPOR: ^"DartGun",
	ToolData.Effect.PIN: ^"Harpoon",
}

## Skinned body mesh (gets the hurt flash overlay); set per model scene.
@export var body_mesh_path: NodePath = ^"Model/Heroine/Skeleton3D/HeroineMesh"
## Parent of the Net/DartGun/Harpoon props, under the hand.R BoneAttachment3D.
@export var hand_tools_path: NodePath = ^"Model/Heroine/Skeleton3D/HandR/HandTools"

var _walking: bool = false
var _flash: StandardMaterial3D
var _blink: Tween
var _recoil: Tween
var _shots: int = 0
var _shown: StringName = &"Net"
var _hand_hold_left: float = 0.0
var _carry_tools: Node3D
@onready var _anim: AnimationPlayer = $Model/AnimationPlayer
@onready var _mesh: MeshInstance3D = get_node(body_mesh_path)
@onready var _hand_tools: Node3D = get_node_or_null(hand_tools_path)

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
	_update_props()

func _process(delta: float) -> void:
	_hand_hold_left = maxf(_hand_hold_left - delta, 0.0)
	_update_props()

## Carry pose of a prop whose handle runs along its local +Y (net, harpoon), in the visual's
## space; the ring / tip faces up-forward so the iso camera sees it.
static func carry_transform() -> Transform3D:
	var y := CARRY_DIR.normalized()
	var x := (Vector3.RIGHT - y * y.dot(Vector3.RIGHT)).normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x, y, z), CARRY_GRIP)

## Copies the carried props under a chest BoneAttachment3D, placed at carry_transform().
func _build_carry() -> void:
	if _hand_tools == null:
		return
	var skeleton := _hand_tools.get_parent().get_parent() as Skeleton3D
	if skeleton == null:
		return
	var bone := skeleton.find_bone(CARRY_BONE)
	if bone < 0:
		return
	var attach := BoneAttachment3D.new()
	attach.name = "Carry"
	attach.bone_name = CARRY_BONE
	skeleton.add_child(attach)
	_carry_tools = Node3D.new()
	_carry_tools.name = "CarryTools"
	attach.add_child(_carry_tools)
	# The attachment follows the chest's pose; place the props from the chest's rest frame.
	var skel_in_visual := global_transform.affine_inverse() * skeleton.global_transform
	var chest := skel_in_visual * skeleton.get_bone_global_rest(bone)
	var local := chest.affine_inverse() * carry_transform()
	for prop_name in CARRIED:
		var src := _hand_tools.get_node_or_null(NodePath(prop_name)) as Node3D
		if src == null:
			continue
		var copy := src.duplicate() as Node3D
		copy.transform = local
		copy.visible = false
		_carry_tools.add_child(copy)

## True while the shown prop rests on the shoulder (no swing, no harpoon shot under way).
func is_carrying() -> bool:
	return _carry_tools != null and _shown in CARRIED and _hand_hold_left <= 0.0 \
			and not (_anim.is_playing() and _anim.current_animation == &"Swing")

## The shoulder copy of a carried prop ("Net", "Harpoon"), or null.
func carried_prop(prop_name: StringName) -> Node3D:
	return _carry_tools.get_node_or_null(NodePath(prop_name)) as Node3D if _carry_tools != null else null

func _update_props() -> void:
	if _hand_tools == null:
		return
	var carrying := is_carrying()
	for prop in _hand_tools.get_children():
		(prop as Node3D).visible = StringName(prop.name) == _shown and not carrying
	if _carry_tools != null:
		for prop in _carry_tools.get_children():
			(prop as Node3D).visible = StringName(prop.name) == _shown and carrying

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
