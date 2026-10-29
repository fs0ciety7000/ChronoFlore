class_name HostileAttack
extends RefCounted
## A hostile plant's attacks: contact hits on every player in reach (and the stun after an accepted
## one), hazards spawned next to the plant, world effects and the attack animation trigger.
## Owned by Plant; behaviors reach it through Plant's thin wrappers.

var _plant: Plant
var _presenter: PlantPresenter
var _stun_left: float = 0.0

func _init(plant: Plant, presenter: PlantPresenter) -> void:
	_plant = plant
	_presenter = presenter

## True while the hostile rests after an accepted contact hit.
func is_stunned() -> bool:
	return _stun_left > 0.0

## Counts the stun down.
func tick_stun(delta: float) -> void:
	_stun_left -= delta

## Adds a hazard next to the plant (same parent: NightSession's Plants root) and starts it.
func spawn_hazard(hazard: Hazard, at: Vector3, telegraph: float) -> Hazard:
	var parent := _plant.get_parent() if _plant.get_parent() != null else _plant
	parent.add_child(hazard)
	hazard.setup(at, telegraph)
	return hazard

## Adds a world-placed effect (ground sign) that dies with the plant but does not follow it.
func add_effect(node: Node3D) -> void:
	node.top_level = true
	_plant.add_child(node)

## Plays the model's Attack so that its strike lands `impact_in` seconds from now (0: at once).
func play_attack(impact_in: float = 0.0) -> void:
	_presenter.play_attack(impact_in)

## Contact with every player (group "heroine") within CONTACT_DISTANCE, each on their own
## invulnerability window (a charge lane can cross the farther player too). An accepted hit
## stuns the hostile and resets its behavior.
func check_contact() -> void:
	if _plant.torpor.is_asleep() or not _plant.is_inside_tree():
		return
	var here := _plant.xz()
	var hit := false
	for node in _plant.get_tree().get_nodes_in_group("heroine"):
		var player := node as Node3D
		if player == null or not player.has_method("take_nightmare_hit"):
			continue
		if Vector2(player.global_position.x, player.global_position.z).distance_to(here) >= Plant.CONTACT_DISTANCE:
			continue
		if player.call("take_nightmare_hit", here) == true:
			hit = true
	if hit:
		_stun_left = Plant.CONTACT_STUN_DURATION
		_plant.reset_behavior() # a charge or a wind-up never outlives the hit
		_presenter.play_attack()
