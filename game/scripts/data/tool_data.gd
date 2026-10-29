class_name ToolData
extends Resource
## Static description of a hero tool, loaded from data/tools/*.tres.

enum Effect { TORPOR, PIN, CAPTURE }

@export var id: StringName
@export var display_name: String
@export var effect: Effect = Effect.CAPTURE
@export var cooldown: float = 0.5
@export var max_range: float = 2.0
@export var projectile_speed: float = 0.0 ## 0 for the net
@export var unlocked_by_default: bool = true
