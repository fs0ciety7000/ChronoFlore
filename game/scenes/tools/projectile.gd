class_name Projectile
extends Area3D
## Straight-line dart or harpoon bolt. Hits the first live plant it touches, then disappears.

## XZ distance at which a plant counts as touched (deterministic twin of the physics overlap).
const HIT_RADIUS := 0.5

var tool_data: ToolData
var direction: Vector2 = Vector2(0, 1)
var travelled: float = 0.0
var _done: bool = false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4 # plants only
	monitoring = true
	body_entered.connect(_on_body_entered)

func launch(p_tool: ToolData, origin: Vector3, dir: Vector2) -> void:
	tool_data = p_tool
	direction = dir.normalized() if dir.length_squared() > 1e-8 else Vector2(0, 1)
	position = origin
	if is_inside_tree():
		reset_physics_interpolation()

func _physics_process(delta: float) -> void:
	step(delta)

## One simulation tick (called by _physics_process; tests call it directly).
func step(delta: float) -> void:
	if _done or tool_data == null:
		return
	var move := minf(tool_data.projectile_speed * delta, tool_data.max_range - travelled)
	position += Vector3(direction.x, 0.0, direction.y) * move
	travelled += move
	if is_inside_tree():
		var here := Vector2(global_position.x, global_position.z)
		for node in get_tree().get_nodes_in_group("plants"):
			var plant := node as Plant
			if plant != null and plant.is_targetable() and plant.xz().distance_to(here) <= HIT_RADIUS:
				_hit(plant)
				return
	if travelled >= tool_data.max_range - 1e-6:
		_finish()

func _on_body_entered(body: Node3D) -> void:
	var plant := body as Plant
	if plant != null and not _done and plant.is_targetable():
		_hit(plant)

func _hit(plant: Plant) -> void:
	plant.hit_by_tool(tool_data.effect)
	_finish()

func _finish() -> void:
	_done = true
	queue_free()
