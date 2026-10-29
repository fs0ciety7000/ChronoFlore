class_name SporeCloud
extends Hazard
## Champi-Panique's burst: a lilac ring pulses around the swelling mushroom (the telegraph), then
## a cloud of spores puffs out and lingers CLOUD_TIME. Inside it the heroine walks at SLOW_FACTOR
## for SLOW_TIME (refreshed while she stays, never stacked). Spores never cost a petal.

const RADIUS := 2.5
const SLOW_FACTOR := 0.5
const SLOW_TIME := 2.0
const CLOUD_TIME := 2.5
const PUFF_COUNT := 14
const PUFF_COLOR := Color(0.86, 0.52, 0.92, 0.5)
## The ring stays this visible while the cloud lingers (the slow zone must read at night).
const LINGER_RING_OPACITY := 0.7
## Seconds for the cloud to puff out to full size.
const PUFF_TIME := 0.25

var _puffs: Array[MeshInstance3D] = []
var _struck_once: bool = false

func _init() -> void:
	radius = RADIUS
	linger = CLOUD_TIME
	rim_color = Color(0.7, 0.42, 0.9)
	fill_color = Color(0.8, 0.6, 0.95)

func _ready() -> void:
	super._ready()
	_build_puffs()

func _strike(target: Node3D) -> bool:
	if not target.has_method("slow"):
		return false
	target.call("slow", SLOW_FACTOR, SLOW_TIME)
	if _struck_once:
		return false # struck is emitted once per cloud
	_struck_once = true
	return true

func _linger_tick(_delta: float) -> void:
	_strike_all()

func _update_visual(progress: float) -> void:
	super._update_visual(progress)
	if mark != null and has_impacted():
		mark.set_opacity(LINGER_RING_OPACITY * clampf((linger - (elapsed - telegraph_time)) / (linger * 0.3), 0.0, 1.0))
	var size := 0.0
	var fade := 1.0
	if has_impacted():
		var after := elapsed - telegraph_time
		size = minf(after / PUFF_TIME, 1.0)
		fade = clampf((linger - after) / (linger * 0.4), 0.0, 1.0)
	for i in _puffs.size():
		var p := _puffs[i]
		p.visible = size > 0.0 and fade > 0.0
		var wobble := 1.0 + 0.08 * sin(elapsed * 3.0 + float(i))
		p.scale = Vector3.ONE * maxf(size * wobble, 0.001)
		var m := p.material_override as StandardMaterial3D
		m.albedo_color.a = PUFF_COLOR.a * fade

func _build_puffs() -> void:
	if not _puffs.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in PUFF_COUNT:
		var sphere := SphereMesh.new()
		var r := rng.randf_range(0.45, 0.8)
		sphere.radius = r
		sphere.height = r * 1.5
		sphere.radial_segments = 10
		sphere.rings = 5
		var m := StandardMaterial3D.new()
		m.albedo_color = PUFF_COLOR
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_BACK
		m.disable_receive_shadows = true
		var puff := MeshInstance3D.new()
		puff.name = "Puff%d" % i
		puff.mesh = sphere
		puff.material_override = m
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * (RADIUS - r * 0.8)
		puff.position = Vector3(cos(a) * d, r * 0.55 + rng.randf() * 0.25, sin(a) * d)
		puff.visible = false
		add_child(puff)
		_puffs.append(puff)
