extends "res://tests/test_case.gd"

func _catalog() -> GameCatalog:
	return load("res://data/catalog.tres") as GameCatalog

func _ids(list: Array[PlantSpecies]) -> Array:
	var ids: Array = []
	for s in list:
		ids.append(s.id)
	return ids

func test_eligible() -> void:
	var c := _catalog()
	assert_eq(_ids(SpawnRules.eligible_capturables(c, 0.0)), [&"revette", &"nostalgerbe", &"calinette"], "0h")
	assert_eq(_ids(SpawnRules.eligible_capturables(c, 2.0)), [&"revette", &"nostalgerbe", &"timidelle", &"calinette", &"souffloine"], "2h")

func test_population_and_nightmares() -> void:
	assert_eq(SpawnRules.target_population(0.0), 6, "pop 0h")
	assert_eq(SpawnRules.target_population(3.0), 7, "pop 3h")
	assert_eq(SpawnRules.target_population(7.9), 8, "pop 7.9h")
	assert_eq(SpawnRules.nightmare_count(0.0), 1, "nm 0h")
	assert_eq(SpawnRules.nightmare_count(3.0), 2, "nm 3h")
	assert_eq(SpawnRules.nightmare_count(6.0), 3, "nm 6h")
	assert_eq(SpawnRules.nightmare_count(8.0), 3, "nm capped")

func test_speed_multiplier() -> void:
	assert_near(SpawnRules.speed_multiplier(5.0), 1.4, 0.0001, "5h")

func test_pick_weighted() -> void:
	var c := _catalog()
	var list: Array[PlantSpecies] = [c.species_by_id(&"revette"), c.species_by_id(&"timidelle")]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var revette := 0
	for i in 600:
		if SpawnRules.pick(list, rng).id == &"revette":
			revette += 1
	var ratio := float(revette) / 600.0
	assert_true(ratio > 0.55 and ratio < 0.80, "revette ratio %s" % ratio)

func test_pick_empty() -> void:
	var rng := RandomNumberGenerator.new()
	assert_true(SpawnRules.pick([] as Array[PlantSpecies], rng) == null, "empty -> null")
