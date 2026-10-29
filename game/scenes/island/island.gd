class_name Island
extends Node3D
## Polyfork terrain diorama with giant dream-plant decor. Gameplay happens on the flat
## central plateau at y = 0, bounded by shape.

@export var shape: IslandShape

func _ready() -> void:
	PolyforkUtil.enable_vertex_colors(self)

## Height of the walkable ground: the slice plays on a flat plateau.
func ground_height() -> float:
	return 0.0
