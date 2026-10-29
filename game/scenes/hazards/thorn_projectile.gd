class_name ThornProjectile
extends Hazard
## Ortie-Regret's thorn: from the spit, a shadow grows on the ground where it will land (the
## telegraph, FLIGHT_TIME), while the thorn arcs over from the plant. Landing on the heroine
## (IMPACT_RADIUS) costs one petal and knocks her back away from the Ortie.

const FLIGHT_TIME := 1.0
const IMPACT_RADIUS := 0.7
## Apex of the arc above the straight line (metres).
const ARC_HEIGHT := 2.2
## The thorn leaves the plant's mouth at this height.
const MOUTH_HEIGHT := 0.6
const STUCK_TIME := 0.35
const THORN_COLOR := Color(0.55, 0.72, 0.72)

var origin: Vector3 = Vector3.ZERO
var _has_origin: bool = false
var _thorn: MeshInstance3D

func _init() -> void:
	radius = IMPACT_RADIUS
	linger = STUCK_TIME
	rim_color = Color(0.24, 0.42, 0.46)
	fill_color = Color(0.3, 0.36, 0.42)

func _ready() -> void:
	super._ready()
	_build_thorn()

## Where the thorn is spat from (world position of the plant's base).
func set_origin(from: Vector3) -> void:
	origin = from
	_has_origin = true
	_update_visual(clampf(elapsed / telegraph_time, 0.0, 1.0))

func origin_xz() -> Vector2:
	return Vector2(origin.x, origin.z)

func _strike(target: Node3D) -> bool:
	if not target.has_method("take_nightmare_hit"):
		return false
	return target.call("take_nightmare_hit", origin_xz() if _has_origin else center_xz()) == true

func _update_visual(progress: float) -> void:
	super._update_visual(progress)
	if _thorn == null:
		return
	var here := global_position if is_inside_tree() else position
	if has_impacted():
		_thorn.position = Vector3(0.0, 0.12, 0.0)
		_thorn.rotation = Vector3(PI, 0.0, 0.0)
		_thorn.visible = elapsed - telegraph_time < linger
		return
	var start := (origin if _has_origin else here) + Vector3(0.0, MOUTH_HEIGHT, 0.0)
	var p := _arc(start, here, progress)
	var ahead := _arc(start, here, minf(progress + 0.02, 1.0))
	_thorn.position = p - here
	var dir := ahead - p
	if dir.length_squared() > 1e-8:
		_thorn.basis = Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT) \
			* Basis(Vector3.RIGHT, -PI * 0.5)

static func _arc(a: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(b, t) + Vector3(0.0, 4.0 * ARC_HEIGHT * t * (1.0 - t), 0.0)

func _build_thorn() -> void:
	if _thorn != null:
		return
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.07
	cone.height = 0.36
	cone.radial_segments = 8
	cone.rings = 1
	var m := StandardMaterial3D.new()
	m.albedo_color = THORN_COLOR
	m.emission_enabled = true
	m.emission = THORN_COLOR
	m.emission_energy_multiplier = 0.3
	_thorn = MeshInstance3D.new()
	_thorn.name = "Thorn"
	_thorn.mesh = cone
	_thorn.material_override = m
	add_child(_thorn)
	_update_visual(0.0)
