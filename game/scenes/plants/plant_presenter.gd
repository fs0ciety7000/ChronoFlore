class_name PlantPresenter
extends RefCounted
## Plant's visual sync, no gameplay: builds the species model (PlantModelVisual) under the
## plant's "Visual" holder, plays the animation of the plant's state, drives the night glow and
## moves the holder every frame (hover height, wander bob, alert tremble).

var model: PlantModelVisual

var _plant: Plant
var _glow: float = 0.0 ## last plant_glow, reapplied whenever the visual is rebuilt
var _anim_t: float = 0.0
var _hover: float = 0.0 ## smoothed model height above the ground

func _init(plant: Plant, rng: RandomNumberGenerator) -> void:
	_plant = plant
	_anim_t = rng.randf() * TAU # desynchronise idle bobs

func holder() -> Node3D:
	return _plant.get_node_or_null("Visual") as Node3D

## Snaps the hover to the behavior's current height (setup, no easing in).
func reset_hover() -> void:
	_hover = _plant.hover_height()

## Replaces the holder's children with the species model.
func build() -> void:
	var visual_holder := holder()
	if visual_holder == null:
		return
	for child in visual_holder.get_children():
		child.queue_free()
	model = null
	var species := _plant.species
	if species == null or species.visual_scene == null:
		return
	var visual := species.visual_scene.instantiate()
	visual_holder.add_child(visual)
	model = visual as PlantModelVisual # owns per-plant material copies
	set_glow(_glow)
	sync_animation()

## Pastel emission driven by the night palette's plant_glow (0..1).
func set_glow(value: float) -> void:
	_glow = value
	if model != null:
		model.set_glow(value)

## Idle/Move/Sleep/Caught on the model, from the state, the torpor and (hostiles) the motion.
func sync_animation() -> void:
	if model != null:
		var hidden := _plant.is_hidden()
		model.play_state(Plant.State.WANDER if hidden else _plant.state, _plant.torpor.is_asleep(),
				not hidden and _plant.is_hostile() and _plant.is_moving())

## Plays the model's Attack so that its strike lands `impact_in` seconds from now (0: at once).
func play_attack(impact_in: float = 0.0) -> void:
	if model != null:
		model.play_attack(impact_in)

## Per-frame holder offset: hover, bob while wandering, tremble while alert.
func animate(delta: float, moving: bool) -> void:
	var visual := holder()
	if visual == null or _plant.state == Plant.State.CAPTURED:
		return # the capture tween owns the visual's scale
	_anim_t += delta
	_hover = lerpf(_hover, _plant.hover_height(), 1.0 - exp(-Plant.HOVER_RATE * delta))
	var offset := Vector3(0.0, _hover, 0.0) # sleep, flight and capture are the model's own animations
	if not _plant.torpor.is_asleep():
		if _plant.state == Plant.State.ALERT:
			offset.x = sin(_anim_t * 70.0) * Plant.TREMBLE_AMPLITUDE
		elif _plant.state == Plant.State.WANDER and moving and not _plant.is_hostile(): # Move hops on its own
			offset.y += absf(sin(_anim_t * Plant.BOB_FREQ)) * Plant.BOB_HEIGHT * 2.0
	visual.position = offset
