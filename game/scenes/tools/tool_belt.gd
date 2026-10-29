class_name ToolBelt
extends Node
## Tool selection, cooldowns and use. Child of Heroine; the night session feeds it the tools.

signal tool_changed(tool: ToolData)
signal tool_used(tool: ToolData)

const PROJECTILE_SCENE := preload("res://scenes/tools/projectile.tscn")
const NET_SWING_SCENE := preload("res://scenes/tools/net_swing.tscn")
const NET_HALF_ANGLE := 60.0
const SWING_FADE := 0.2

var tools: Array[ToolData] = []
var index: int = 0
## Used when the parent is not a Heroine (which supplies its own aim_source).
var aim_source: AimAssist.Source = AimAssist.Source.MOVE

var _cooldowns: Dictionary = {} ## tool id -> seconds left

func set_tools(p_tools: Array[ToolData]) -> void:
	tools = p_tools
	index = clampi(index, 0, maxi(tools.size() - 1, 0))
	tool_changed.emit(current())

func current() -> ToolData:
	if tools.is_empty():
		return null
	return tools[index]

func select(i: int) -> void:
	if tools.is_empty() or i < 0 or i >= tools.size() or i == index:
		return
	index = i
	tool_changed.emit(current())

func cycle(step: int) -> void:
	if tools.size() < 2:
		return
	index = posmod(index + step, tools.size())
	tool_changed.emit(current())

func tick(delta: float) -> void:
	for id in _cooldowns.keys():
		var left: float = maxf(float(_cooldowns[id]) - delta, 0.0)
		if left <= 0.0:
			_cooldowns.erase(id)
		else:
			_cooldowns[id] = left

## False while the tool is on cooldown (or there is no tool).
func try_use(origin: Vector3, aim_dir: Vector2) -> bool:
	var tool := current()
	if tool == null or _cooldowns.has(tool.id):
		return false
	var dir := aim_dir.normalized() if aim_dir.length_squared() > 1e-8 else Vector2(0, 1)
	_cooldowns[tool.id] = tool.cooldown
	if tool.effect == ToolData.Effect.CAPTURE:
		_use_net(tool, origin, dir)
	else:
		_fire(tool, origin, dir)
	tool_used.emit(tool)
	return true

func _live_plants() -> Array[Plant]:
	var result: Array[Plant] = []
	if not is_inside_tree():
		return result
	for node in get_tree().get_nodes_in_group("plants"):
		var plant := node as Plant
		if plant != null and plant.state != Plant.State.BURROWED and not plant.is_hidden() \
				and plant.state != Plant.State.CAPTURED and plant.state != Plant.State.ESCAPED:
			result.append(plant)
	return result

func _use_net(tool: ToolData, origin: Vector3, dir: Vector2) -> void:
	var o2 := Vector2(origin.x, origin.z)
	var in_reach: Array[Plant] = []
	for plant in _live_plants():
		if Steering.in_cone(o2, dir, plant.xz(), NET_HALF_ANGLE, tool.max_range):
			in_reach.append(plant)
	in_reach.sort_custom(func(a: Plant, b: Plant) -> bool:
		return a.xz().distance_squared_to(o2) < b.xz().distance_squared_to(o2))
	_spawn_swing(origin, dir)
	for plant in in_reach:
		if plant.hit_by_tool(tool.effect):
			return

func _fire(tool: ToolData, origin: Vector3, dir: Vector2) -> void:
	var o2 := Vector2(origin.x, origin.z)
	var targets := PackedVector2Array()
	for plant in _live_plants():
		targets.append(plant.xz())
	var source := aim_source
	var parent := get_parent()
	if parent is Heroine:
		source = (parent as Heroine).aim_source
	var shot := AimAssist.assisted_direction(o2, dir, targets, tool.max_range, source)
	var proj := PROJECTILE_SCENE.instantiate() as Projectile
	var host := _spawn_parent()
	if host == null:
		proj.free()
		return
	host.add_child(proj)
	proj.launch(tool, origin, shot)

func _spawn_swing(origin: Vector3, dir: Vector2) -> void:
	var host := _spawn_parent()
	if host == null:
		return
	var swing := NET_SWING_SCENE.instantiate() as Node3D
	host.add_child(swing)
	swing.position = origin
	swing.rotation.y = atan2(dir.x, dir.y)
	var tween := swing.create_tween()
	tween.tween_property(swing, "scale", Vector3(1.0, 1.0, 0.1), SWING_FADE)
	tween.tween_callback(swing.queue_free)

func _spawn_parent() -> Node:
	if not is_inside_tree():
		return null
	var scene := get_tree().current_scene
	if scene != null:
		return scene
	var p := get_parent()
	return p.get_parent() if p != null and p.get_parent() != null else p
