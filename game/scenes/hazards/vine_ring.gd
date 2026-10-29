class_name VineRing
extends Hazard
## Lierre-Jalousie's trap: a lime ring pulses under the heroine for TELEGRAPH seconds, then soft
## ivy vines spring up in a circle. Caught inside, she loses one petal (no knockback: the vines
## hold her) and is immobilized HOLD_TIME, only when the hit is accepted, so overlapping rings
## never chain-hold her within one invulnerability window.

const RADIUS := 1.2
const TELEGRAPH := 1.0
const HOLD_TIME := 1.0
const VINE_COUNT := 9
const VINE_HEIGHT := 0.55
## Seconds for the vines to spring up / sink back.
const GROW_TIME := 0.12
const VINE_COLOR := Color(0.62, 0.8, 0.36)
const LEAF_COLOR := Color(0.78, 0.9, 0.42)

var _vines: Array[Node3D] = []

func _init() -> void:
	radius = RADIUS
	linger = HOLD_TIME
	rim_color = Color(0.55, 0.78, 0.18)
	fill_color = Color(0.82, 0.95, 0.5)

func _ready() -> void:
	super._ready()
	_build_vines()

func _strike(target: Node3D) -> bool:
	if not target.has_method("take_nightmare_hit"):
		return false
	if target.call("take_nightmare_hit") != true:
		return false
	if target.has_method("immobilize"):
		target.call("immobilize", HOLD_TIME)
	return true

func _update_visual(progress: float) -> void:
	super._update_visual(progress)
	var grow := 0.0
	if has_impacted():
		var after := elapsed - telegraph_time
		grow = minf(after / GROW_TIME, 1.0) * minf((linger - after) / GROW_TIME, 1.0)
	for v in _vines:
		v.scale = Vector3(1.0, maxf(grow, 0.001), 1.0)
		v.visible = grow > 0.0

func _build_vines() -> void:
	if not _vines.is_empty():
		return
	var stem := StandardMaterial3D.new()
	stem.albedo_color = VINE_COLOR
	stem.emission_enabled = true
	stem.emission = VINE_COLOR
	stem.emission_energy_multiplier = 0.25
	var leaf_mat := stem.duplicate() as StandardMaterial3D
	leaf_mat.albedo_color = LEAF_COLOR
	leaf_mat.emission = LEAF_COLOR
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.06
	capsule.height = VINE_HEIGHT
	capsule.radial_segments = 8
	capsule.rings = 2
	var leaf := SphereMesh.new()
	leaf.radius = 0.09
	leaf.height = 0.07
	leaf.radial_segments = 8
	leaf.rings = 4
	for i in VINE_COUNT:
		var a := TAU * float(i) / VINE_COUNT
		var root := Node3D.new()
		root.name = "Vine%d" % i
		root.position = Vector3(cos(a), 0.0, sin(a)) * (RADIUS * 0.92)
		var tilt := Node3D.new()
		tilt.rotation = Vector3(0.0, -a, 0.35) # leans in towards the centre
		root.add_child(tilt)
		var body := MeshInstance3D.new()
		body.mesh = capsule
		body.material_override = stem
		body.position = Vector3(0.0, VINE_HEIGHT * 0.5, 0.0)
		tilt.add_child(body)
		var tip := MeshInstance3D.new()
		tip.mesh = leaf
		tip.material_override = leaf_mat
		tip.position = Vector3(-0.06, VINE_HEIGHT * 0.92, 0.0)
		tip.rotation = Vector3(0.0, 0.0, 0.6)
		tilt.add_child(tip)
		root.visible = false
		add_child(root)
		_vines.append(root)
