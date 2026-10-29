class_name GameCatalog
extends Resource
## All static game content: species, tools, unlock milestones and dawn memories.

@export var species: Array[PlantSpecies] = []
@export var tools: Array[ToolData] = []
@export var milestones: Array[UnlockMilestone] = []
@export var dawn_memories: PackedStringArray = PackedStringArray() ## ordered

func species_by_id(id: StringName) -> PlantSpecies:
	for s in species:
		if s.id == id:
			return s
	return null

func tool_by_id(id: StringName) -> ToolData:
	for t in tools:
		if t.id == id:
			return t
	return null
