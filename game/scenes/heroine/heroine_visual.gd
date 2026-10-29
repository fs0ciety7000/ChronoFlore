extends Node3D
## Placeholder chibi heroine built from primitives (~1.1 m, head ~45 % of the height, faces +Z).

const SKIN := Color("5a3a2a")
const HAIR := Color("1a1416")
const STRIPES: Array[Color] = [Color("6fbf73"), Color("e0524f"), Color("f2994a"), Color("9b6fd0")]
const GLASSES := Color("f08aa8")
const GOLD := Color("e6c15a")
const HEAD_RADIUS := 0.25
const HEAD_Y := 0.85
const BODY_HEIGHT := 0.6
const WALK_PERIOD := 0.18
const WALK_STRETCH := 0.08

var _body: Node3D
var _materials: Array[StandardMaterial3D] = []
var _walking: bool = false
var _tween: Tween
var _blink: Tween

func _ready() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_build()

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	m.emission_enabled = true
	m.emission = Color.WHITE
	m.emission_energy_multiplier = 0.0
	_materials.append(m)
	return m

func _add(mesh: Mesh, c: Color, pos: Vector3, rot_x_deg: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c)
	mi.position = pos
	mi.rotation_degrees.x = rot_x_deg
	_body.add_child(mi)
	return mi

func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s

func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	return t

func _build() -> void:
	# Torso: skin-toned capsule hidden under four stripe rings.
	var ring_h := (BODY_HEIGHT - 0.1) / 4.0
	for i in 4:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.2
		cyl.bottom_radius = 0.2
		cyl.height = ring_h
		_add(cyl, STRIPES[i], Vector3(0, 0.05 + ring_h * (i + 0.5), 0))
	# Legs stub.
	var legs := CylinderMesh.new()
	legs.top_radius = 0.12
	legs.bottom_radius = 0.12
	legs.height = 0.1
	_add(legs, SKIN, Vector3(0, 0.05, 0))
	# Head and hair cap.
	_add(_sphere(HEAD_RADIUS), SKIN, Vector3(0, HEAD_Y, 0))
	_add(_sphere(HEAD_RADIUS * 0.96), HAIR, Vector3(0, HEAD_Y + 0.03, -0.04))
	# Face: round pink glasses (ring faces +Z) and a smile bar.
	for sx in [-1.0, 1.0]:
		_add(_torus(0.045, 0.065), GLASSES, Vector3(0.09 * sx, HEAD_Y + 0.02, 0.215), 90.0)
	var smile := _torus(0.02, 0.04)
	_add(smile, Color("fff5ee"), Vector3(0, HEAD_Y - 0.09, 0.215), 90.0).scale = Vector3(1.4, 1.0, 0.6)
	# Braids: chains of black spheres hanging on both sides.
	for sx in [-1.0, 1.0]:
		for j in 5:
			_add(_sphere(0.05 - j * 0.004), HAIR, Vector3(0.24 * sx + 0.01 * j * sx, HEAD_Y - 0.05 - j * 0.09, -0.02))
	# Golden necklace.
	_add(_torus(0.012, 0.19), GOLD, Vector3(0, 0.6, 0))

func set_walking(on: bool) -> void:
	if on == _walking:
		return
	_walking = on
	if _tween != null:
		_tween.kill()
	if _body == null:
		return
	if on:
		_tween = create_tween().set_loops()
		_tween.tween_property(_body, "scale", Vector3(1.0 + WALK_STRETCH, 1.0 - WALK_STRETCH, 1.0 + WALK_STRETCH), WALK_PERIOD)
		_tween.tween_property(_body, "scale", Vector3(1.0 - WALK_STRETCH, 1.0 + WALK_STRETCH, 1.0 - WALK_STRETCH), WALK_PERIOD)
	else:
		_tween = create_tween()
		_tween.tween_property(_body, "scale", Vector3.ONE, WALK_PERIOD)

## Quick white flash while invulnerable.
func blink_hurt() -> void:
	if _blink != null:
		_blink.kill()
	_blink = create_tween().set_loops(3)
	_blink.tween_method(_set_flash, 0.0, 1.0, 0.08)
	_blink.tween_method(_set_flash, 1.0, 0.0, 0.08)

func _set_flash(v: float) -> void:
	for m in _materials:
		m.emission_energy_multiplier = v
