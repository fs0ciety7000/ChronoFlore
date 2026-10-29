extends Node
## Autoload `GameState`: the catalog, the persistent Herbarium and the last night's result.

signal herbarium_changed

## Who plays the night. Only the heroine dreams: the hero is a figure of her dream.
enum Mode { SOLO_HEROINE, SOLO_HERO, COOP }

const NIGHT_SCENE := "res://scenes/night/night.tscn"

var catalog: GameCatalog = load("res://data/catalog.tres")
var herbarium: Herbarium = Herbarium.new()
var save_path: String = SaveStore.DEFAULT_PATH
var last_night: Dictionary = {} ## filled by finish_night, read by the wake screen
## Last chosen mode; kept for the whole session (title and wake screens do not reset it).
var mode: Mode = Mode.SOLO_HEROINE

## Species discovered since begin_night(), in discovery order.
var _night_discoveries: Array[StringName] = []

func _ready() -> void:
	load_save()

func load_save() -> void:
	herbarium = SaveStore.load_or_new(save_path)
	herbarium_changed.emit()

## Clears the per-night bookkeeping (called when a night session starts).
func begin_night() -> void:
	_night_discoveries.clear()

## Counts a capture (or a Ronce sleep). Saves at once on a discovery or a new detail so
## progress survives a tab closed mid-night.
func record(species: PlantSpecies) -> Dictionary:
	var result := herbarium.record(species)
	if bool(result["new_species"]):
		_night_discoveries.append(species.id)
	if bool(result["new_species"]) or int(result["new_detail"]) >= 0:
		_save()
	herbarium_changed.emit()
	return result

## Applies records and milestones, saves, stores and returns the night summary.
func finish_night(minutes: int, full: bool, captures: Array[StringName]) -> Dictionary:
	var dawn_memory := herbarium.register_night(minutes, full, catalog)
	var unlocked := herbarium.apply_milestones(catalog)
	_save()
	last_night = {
		"minutes": minutes,
		"full": full,
		"captures": captures.duplicate(),
		"new_species": _night_discoveries.duplicate(),
		"unlocked": unlocked,
		"dawn_memory": dawn_memory,
		"best_minutes": herbarium.best_minutes,
	}
	_night_discoveries.clear()
	herbarium_changed.emit()
	return last_night

## Starts a night with the current mode (the wake screen's "next night").
func start_night() -> void:
	start_night_with(mode)

func start_night_with(p_mode: Mode) -> void:
	mode = p_mode
	get_tree().change_scene_to_file(NIGHT_SCENE)

func _save() -> void:
	var err := SaveStore.save(herbarium, save_path)
	if err != OK:
		push_warning("GameState: save failed (%s)" % error_string(err))
