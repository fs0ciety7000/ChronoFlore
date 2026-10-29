class_name Herbarium
extends RefCounted
## Persistent progression: per-species counts, unlocked tools, records and dawn memories.

const SAVE_VERSION := 1
const DETAIL_THRESHOLDS := [5, 15]

## StringName -> int: captures per species (every species is capturable since Task B3; a hostile
## counts only when netted asleep). Saves from before B3 counted a Ronce that was only put to
## sleep: on load such a count stays and now reads as a captured capturable species (accepted).
var counts: Dictionary = {}
var unlocked_tools: Array[StringName] = []
var best_minutes: int = 0
var full_nights: int = 0
var next_dawn_memory: int = 0

## Counts one capture. new_detail is the detail index (0 or 1) revealed by
## this count, or -1.
func record(species: PlantSpecies) -> Dictionary:
	var n: int = int(counts.get(species.id, 0)) + 1
	counts[species.id] = n
	return {"new_species": n == 1, "new_detail": DETAIL_THRESHOLDS.find(n)}

func is_discovered(id: StringName) -> bool:
	return int(counts.get(id, 0)) > 0

func revealed_details(id: StringName) -> int:
	var n: int = int(counts.get(id, 0))
	var revealed := 0
	for threshold: int in DETAIL_THRESHOLDS:
		if n >= threshold:
			revealed += 1
	return revealed

func discovered_capturable_count(catalog: GameCatalog) -> int:
	var total := 0
	for s in catalog.species:
		if s.capturable and is_discovered(s.id):
			total += 1
	return total

## Unlocks the tools of every reached milestone. Returns the newly unlocked tool ids.
func apply_milestones(catalog: GameCatalog) -> Array[StringName]:
	var newly: Array[StringName] = []
	var found := discovered_capturable_count(catalog)
	for m in catalog.milestones:
		if found >= m.capturable_species_required and not unlocked_tools.has(m.reward_tool_id):
			unlocked_tools.append(m.reward_tool_id)
			newly.append(m.reward_tool_id)
	return newly

## Default tools plus unlocked ones, in catalog order.
func available_tools(catalog: GameCatalog) -> Array[StringName]:
	var result: Array[StringName] = []
	for t in catalog.tools:
		if t.unlocked_by_default or unlocked_tools.has(t.id):
			result.append(t.id)
	return result

## Updates records. On a full night returns the dawn memory index revealed (then advances),
## or -1 when not a full night or when every memory has been read.
func register_night(minutes: int, full: bool, catalog: GameCatalog) -> int:
	best_minutes = maxi(best_minutes, minutes)
	if not full:
		return -1
	full_nights += 1
	if next_dawn_memory >= catalog.dawn_memories.size():
		return -1
	var revealed := next_dawn_memory
	next_dawn_memory += 1
	return revealed

func to_dict() -> Dictionary:
	var c := {}
	for id: StringName in counts:
		c[String(id)] = counts[id]
	var tools: Array[String] = []
	for t in unlocked_tools:
		tools.append(String(t))
	return {
		"version": SAVE_VERSION,
		"counts": c,
		"unlocked_tools": tools,
		"best_minutes": best_minutes,
		"full_nights": full_nights,
		"next_dawn_memory": next_dawn_memory,
	}

## Returns null if the version is not SAVE_VERSION or the shape is invalid.
static func from_dict(d: Dictionary) -> Herbarium:
	if not _is_number(d.get("version")) or int(d["version"]) != SAVE_VERSION:
		return null
	if not (d.get("counts") is Dictionary) or not (d.get("unlocked_tools") is Array):
		return null
	for key: String in ["best_minutes", "full_nights", "next_dawn_memory"]:
		if not _is_number(d.get(key)):
			return null
	var h := Herbarium.new()
	var raw_counts: Dictionary = d["counts"]
	for k: Variant in raw_counts:
		if not (k is String) or not _is_number(raw_counts[k]):
			return null
		h.counts[StringName(k)] = maxi(int(raw_counts[k]), 0)
	for t: Variant in d["unlocked_tools"]:
		if not (t is String):
			return null
		h.unlocked_tools.append(StringName(t))
	h.best_minutes = maxi(int(d["best_minutes"]), 0)
	h.full_nights = maxi(int(d["full_nights"]), 0)
	h.next_dawn_memory = maxi(int(d["next_dawn_memory"]), 0)
	return h

static func _is_number(v: Variant) -> bool:
	return v is int or v is float
