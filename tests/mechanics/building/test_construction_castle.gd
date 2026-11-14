extends "res://tests/helpers/test_helpers.gd"
## Buildable extra castles through ConstructionPlacer (#527).


func _extra_castle_anchor(world, quarter_turns := 0, origin: Variant = null) -> Variant:
	var s: Structure = StructurePlacer.load_named("castle")
	if s == null:
		return null
	s = Structure.rotated(s, quarter_turns)
	var base: Vector2i = origin if origin is Vector2i else world.spawn_point + Vector2i(24, 0)
	for r in range(0, 56):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cell := base + Vector2i(dx, dy)
				var foot: Array = StructurePlacer.footprint(s, cell).keys()
				if foot.is_empty():
					continue
				if foot.all(func(c): return world.get_cell_source_id(0, c) != -1 and world.predicted_clear(c)):
					return cell
	return null


func _clear_castle_anchor(world, quarter_turns := 0) -> Variant:
	var s: Structure = StructurePlacer.load_named("castle")
	if s == null:
		return null
	s = Structure.rotated(s, quarter_turns)
	for seed_value in [11, 42, 99, 7, 1, 3, 5]:
		world.apply_map_params(_spawn_params(seed_value, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell: Vector2i in world.get_used_cells(0):
			var cells: Array = StructurePlacer.footprint(s, cell).keys()
			if cells.is_empty():
				continue
			if cells.all(func(c): return world.get_cell_source_id(0, c) != -1 and world.predicted_clear(c)):
				return cell
	return null


func _test_construction_placer_castle() -> int:
	## A clear land anchor places castle for 50 wood with the builder's flag.
	## Water, overlap, short wood and multiplayer are refused without spending.
	print("-- test_construction_placer_castle")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var inventory: Inventory = scene.get_node("Inventory")
	var placer := ConstructionPlacer.new(world)
	var anchor: Variant = _clear_castle_anchor(world)
	if anchor == null:
		printerr("FAIL construction_placer_castle: no clear castle footprint")
		scene.queue_free()
		return 1
	var cells: Array[Vector2i] = [anchor]
	inventory.add(Inventory.WOOD, 49)
	var reasons := placer.can_place(BuildCosts.CASTLE, cells, inventory)
	if ConstructionPlacer.NOT_ENOUGH_WOOD not in reasons or placer.place(BuildCosts.CASTLE, cells, inventory) \
			or inventory.count_of(Inventory.WOOD) != 49:
		printerr("FAIL construction_placer_castle: short wood gave %s wood %d" % [reasons, inventory.count_of(Inventory.WOOD)])
		fail += 1
	inventory.add(Inventory.WOOD, 1)
	var before := inventory.count_of(Inventory.WOOD)
	if not placer.place(BuildCosts.CASTLE, cells, inventory) \
			or inventory.count_of(Inventory.WOOD) != before - 50:
		printerr("FAIL construction_placer_castle: place wood %d" % inventory.count_of(Inventory.WOOD))
		fail += 1
	else:
		var placed: Dictionary = world.placed_structures()
		var owner_id: int = scene.multiplayer.get_unique_id()
		var entry: Dictionary = placed[placed.keys()[0]]
		if entry.get("name") != "castle" or entry.get("owner") != owner_id:
			printerr("FAIL construction_placer_castle: entry %s" % entry)
			fail += 1
	inventory.add(Inventory.WOOD, 50)
	reasons = placer.can_place(BuildCosts.CASTLE, cells, inventory)
	if ConstructionPlacer.OCCUPIED not in reasons or placer.place(BuildCosts.CASTLE, cells, inventory):
		printerr("FAIL construction_placer_castle: overlap gave %s" % reasons)
		fail += 1
	var water_anchor := Vector2i(1 << 20, 0)
	for cell in world.get_used_cells(0):
		if world.predict_cell(cell)[0] == TileCatalog.WATER and not world.has_bridge(cell):
			water_anchor = cell
			break
	if water_anchor.x != 1 << 20:
		var wcells: Array[Vector2i] = [water_anchor]
		reasons = placer.can_place(BuildCosts.CASTLE, wcells, inventory)
		if ConstructionPlacer.WRONG_GROUND not in reasons or placer.place(BuildCosts.CASTLE, wcells, inventory):
			printerr("FAIL construction_placer_castle: water gave %s" % reasons)
			fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_construction_placer_castle")
	return fail


func _test_build_castle_save_round_trip() -> int:
	## A rotated extra castle survives save and reload with owner and rotation.
	print("-- test_build_castle_save_round_trip")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("CanvasLayer2/MainMenu").hide()
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	var params := _spawn_params(7, 0.0)
	params.ensure_seeds()
	scene.world_params = params
	scene._apply_params_to_world(params)
	if not world.place_start_castle(1):
		printerr("FAIL build_castle_save_round_trip: no starting castle")
		scene.queue_free()
		return 1
	var anchor: Variant = _extra_castle_anchor(world, 1)
	if anchor == null:
		printerr("FAIL build_castle_save_round_trip: no spot for a second castle")
		scene.queue_free()
		return 1
	var castle := StructurePlacer.load_named("castle")
	if world.place_structure(castle, anchor, 1, 1) <= 0:
		printerr("FAIL build_castle_save_round_trip: could not place second castle")
		scene.queue_free()
		return 1
	var want: Array = world.structures_for_sync()
	var result: Dictionary = scene.get_node("CanvasLayer1/InGameMenu").save_world()
	if result["error"] != "":
		printerr("FAIL build_castle_save_round_trip: save %s" % result["error"])
		fail += 1
	var map_gen = root.get_node("MapGen")
	map_gen.load_map_inputs(result["path"])
	scene.world_params = map_gen.params.duplicate_params()
	scene._apply_params_to_world(scene.world_params)
	var restored: int = scene._restore_loaded_world()
	StructureSaves.adopt_start_castle(world, 1)
	if restored != want.size() or str(world.structures_for_sync()) != str(want):
		printerr("FAIL build_castle_save_round_trip: restored %d got %s want %s"
				% [restored, world.structures_for_sync(), want])
		fail += 1
	var second := {}
	for entry in want:
		if str(entry[0]) == "castle" and entry.size() >= 4 and int(entry[3]) == 1:
			second = {"anchor": entry[2], "rotation": int(entry[3])}
	if second.is_empty():
		printerr("FAIL build_castle_save_round_trip: want row had no rotated castle %s" % want)
		fail += 1
	else:
		var found := false
		for p in world.placed_structures().values():
			if p["name"] == "castle" and p["anchor"] == second["anchor"] \
					and int(p.get("rotation", 0)) == second["rotation"]:
				found = true
				break
		if not found:
			printerr("FAIL build_castle_save_round_trip: rotated castle missing after reload")
			fail += 1
	DirAccess.remove_absolute(result["path"])
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_build_castle_save_round_trip")
	return fail