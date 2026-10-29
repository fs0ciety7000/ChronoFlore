class_name Island
extends Node3D
## Hand-made pastel diorama island (game/assets/custom/island) with its decor. Gameplay happens
## on the flat meadow at y = 0, bounded by shape (outline minus the pond obstacle).

@export var shape: IslandShape

## Height of the walkable ground: the meadow is flat.
func ground_height() -> float:
	return 0.0
