extends "res://tests/test_case.gd"

func _catalog() -> GameCatalog:
	return load("res://data/catalog.tres") as GameCatalog

func test_catalog_loads() -> void:
	var c := _catalog()
	assert_true(c != null, "catalog loads")
	assert_eq(c.species.size(), 12, "12 species")
	assert_eq(c.tools.size(), 3, "3 tools")
	assert_eq(c.milestones.size(), 1, "1 milestone")
	assert_eq(c.dawn_memories.size(), 3, "3 dawn memories")

func test_species_values() -> void:
	var c := _catalog()
	var rows := [
		[&"revette", "Rêvette", "joie légère", PlantSpecies.Rarity.COMMON, true, 4.5, 0.0, PlantSpecies.Behavior.DARTER],
		[&"nostalgerbe", "Nostalgerbe", "nostalgie", PlantSpecies.Rarity.COMMON, true, 3.5, 0.0, PlantSpecies.Behavior.ZIGZAG],
		[&"timidelle", "Timidelle", "timidité", PlantSpecies.Rarity.UNCOMMON, true, 3.0, 2.0, PlantSpecies.Behavior.BURROWER],
		[&"ronce_angoisse", "Ronce-Angoisse", "angoisse", PlantSpecies.Rarity.COMMON, true, 1.2, 0.0, PlantSpecies.Behavior.STALKER],
		[&"calinette", "Câlinette", "tendresse", PlantSpecies.Rarity.COMMON, true, 3.0, 0.0, PlantSpecies.Behavior.SHY_APPROACH],
		[&"souffloine", "Souffloine", "insouciance", PlantSpecies.Rarity.UNCOMMON, true, 4.3, 1.0, PlantSpecies.Behavior.HOPPER],
		[&"melancolys", "Mélancolys", "mélancolie", PlantSpecies.Rarity.UNCOMMON, true, 2.2, 3.0, PlantSpecies.Behavior.POND_SEEKER],
		[&"lumiole", "Lumiole", "espoir", PlantSpecies.Rarity.RARE, true, 6.0, 4.0, PlantSpecies.Behavior.FLOATER],
		[&"croque_colere", "Croque-Colère", "colère", PlantSpecies.Rarity.UNCOMMON, true, 1.6, 2.0, PlantSpecies.Behavior.CHARGER],
		[&"lierre_jalousie", "Lierre-Jalousie", "jalousie", PlantSpecies.Rarity.UNCOMMON, true, 1.0, 3.0, PlantSpecies.Behavior.ROOT_TRAP],
		[&"ortie_regret", "Ortie-Regret", "regret", PlantSpecies.Rarity.RARE, true, 0.0, 4.0, PlantSpecies.Behavior.SPITTER],
		[&"champi_panique", "Champi-Panique", "panique", PlantSpecies.Rarity.RARE, true, 1.4, 5.0, PlantSpecies.Behavior.SPORE],
	]
	for r: Array in rows:
		var s := c.species_by_id(r[0])
		assert_true(s != null, "found %s" % r[0])
		if s == null:
			continue
		assert_eq(s.display_name, r[1], "%s name" % r[0])
		assert_eq(s.emotion, r[2], "%s emotion" % r[0])
		assert_eq(s.rarity, r[3], "%s rarity" % r[0])
		assert_eq(s.capturable, r[4], "%s capturable" % r[0])
		assert_near(s.base_speed, r[5], 0.0001, "%s speed" % r[0])
		assert_near(s.min_hour, r[6], 0.0001, "%s min_hour" % r[0])
		assert_eq(s.behavior, r[7], "%s behavior" % r[0])
	assert_eq(c.species_by_id(&"revette").minutes_reward(), 20, "revette reward")
	assert_eq(c.species_by_id(&"timidelle").minutes_reward(), 40, "timidelle reward")
	assert_eq(c.species_by_id(&"ronce_angoisse").minutes_reward(), 40, "ronce reward (captured asleep)")
	var net := c.tool_by_id(&"net")
	assert_eq(net.effect, ToolData.Effect.CAPTURE, "net effect")
	assert_near(net.max_range, 2.0, 0.0001, "net range")
	var h := c.tool_by_id(&"harpoon")
	assert_eq(h.effect, ToolData.Effect.PIN, "harpoon effect")
	assert_false(h.unlocked_by_default, "harpoon locked")
	assert_near(h.cooldown, 2.5, 0.0001, "harpoon cooldown")
	var t := c.tool_by_id(&"tranquilizer")
	assert_eq(t.effect, ToolData.Effect.TORPOR, "tranq effect")
	assert_near(t.projectile_speed, 18.0, 0.0001, "tranq speed")
	assert_eq(c.milestones[0].capturable_species_required, 4, "milestone count")
	assert_eq(c.milestones[0].reward_tool_id, &"harpoon", "milestone tool")

func test_each_species_has_texts() -> void:
	for s in _catalog().species:
		assert_false(s.fragment.strip_edges().is_empty(), "%s fragment" % s.id)
		assert_true(s.fragment.begins_with("(provisoire) "), "%s fragment prefix" % s.id)
		assert_eq(s.details.size(), 2, "%s details" % s.id)
	for m in _catalog().dawn_memories:
		assert_true(m.begins_with("(provisoire) "), "dawn memory prefix")

func test_lookup() -> void:
	var c := _catalog()
	assert_eq(c.species_by_id(&"timidelle").display_name, "Timidelle", "lookup species")
	assert_true(c.tool_by_id(&"nope") == null, "unknown tool null")
	assert_true(c.species_by_id(&"nope") == null, "unknown species null")
