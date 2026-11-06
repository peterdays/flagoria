extends "res://tests/helpers/test_helpers.gd"
## Placed structures, tower owners and free-form walls in world saves
## (world.structures, #42).


func _test_structure_save_round_trip() -> int:
	## The starting castle, a wooden tower the mobs hold and a three-cell
	## palisade saved from the in-game menu come back from the load before
	## any chunk is drawn: same placements in the same order, the tower's
	## mob flag, the walls, and the castle's gate front as the spawn, so no
	## second castle is placed. Bad entries are dropped; the version 1 and 2
	## fixtures (no structures) load with none and still get a castle.
	print("-- test_structure_save_round_trip")
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
		printerr("FAIL structure_save_round_trip: no starting castle on seed 7")
		scene.queue_free()
		return 1
	var front: Vector2i = world.spawn_point
	var tower := StructurePlacer.load_named("tower_wood")
	var anchor: Variant = StartCastle.find_anchor(world, tower, front + Vector2i(12, 0))
	var tower_id: int = world.place_structure(tower, anchor, StructurePlacer.OWNER_MOBS) if anchor != null else -1
	var walls: Array[Vector2i] = []
	for r in range(6, 40):
		var start: Vector2i = front + Vector2i(-r, r)
		var run: Array[Vector2i] = [start, start + Vector2i.RIGHT, start + Vector2i.RIGHT * 2]
		if run.all(func(c: Vector2i) -> bool: return world.predicted_clear(c) and not world._structures.has_cell(c)):
			walls = run
			break
	if tower_id <= 0 or walls.is_empty() or not world.place_wall_cells(walls):
		printerr("FAIL structure_save_round_trip: setup tower %s walls %s" % [tower_id, walls])
		scene.queue_free()
		return 1
	var want: Array = world.structures_for_sync()

	var map_gen = root.get_node("MapGen")
	var before: MapGenParams = map_gen.params
	var result: Dictionary = scene.get_node("CanvasLayer1/InGameMenu").save_world()
	var file = JSON.parse_string(FileAccess.get_file_as_string(result["path"])) if result["error"] == "" else null
	var section: Dictionary = file["world"]["structures"] if file is Dictionary else {}
	var entries := 0
	for chunk in section:
		entries += section[chunk].size()
	if entries != 2 + walls.size():
		printerr("FAIL structure_save_round_trip: save %s wrote structures %s, want 2 placements and %d walls" % [result["error"], section, walls.size()])
		fail += 1

	map_gen.load_map_inputs(result["path"])
	scene.world_params = map_gen.params.duplicate_params()
	scene._apply_params_to_world(scene.world_params)
	var drawn_before: int = world.get_used_cells(0).size()
	var restored: int = scene._restore_loaded_world()
	var adopted := StructureSaves.adopt_start_castle(world, 1)
	if drawn_before != 0 or restored != 2 + walls.size() or not adopted or world.spawn_point != front:
		printerr("FAIL structure_save_round_trip: restored %d (drawn first %d), castle adopted %s, spawn %s want %s"
				% [restored, drawn_before, adopted, world.spawn_point, front])
		fail += 1
	if str(world.structures_for_sync()) != str(want):
		printerr("FAIL structure_save_round_trip: placements %s, want %s" % [world.structures_for_sync(), want])
		fail += 1
	var towers: Dictionary = world._structures.towers()
	for id in towers:
		var flag_want := TileCatalog.PROP_FLAG_MOBS if world._structures.owner_of(id) == StructurePlacer.OWNER_MOBS else TileCatalog.PROP_FLAG_BLUE
		for c: Vector2i in towers[id]:
			if world.predict_cell(c)[1] != flag_want:
				printerr("FAIL structure_save_round_trip: flag %s of tower %d is %s, want %s" % [c, id, world.predict_cell(c)[1], flag_want])
				fail += 1
	for c in walls:
		if not world.has_wall(c):
			printerr("FAIL structure_save_round_trip: wall %s did not come back" % c)
			fail += 1
	DirAccess.remove_absolute(result["path"])

	# Entries a load must drop or leave to other readers.
	scene._apply_params_to_world(params)
	var bad := {"0,0": {"1,1": {"structure": "no_such_thing", "owner": 1}, "x": {"structure": "castle"}, "2,2": {"cut": "tree"}}}
	if StructureSaves.restore(bad, world) != 0 or not world.placed_structures().is_empty():
		printerr("FAIL structure_save_round_trip: bad entries placed %s" % world.placed_structures())
		fail += 1

	# Older saves (no structures) load with none, so the host places a castle.
	for fixture in ["res://tests/fixtures/world_save_v1.json", "res://tests/fixtures/world_save_v2.json"]:
		var err: String = map_gen.load_map_inputs(fixture)
		scene.world_params = map_gen.params.duplicate_params()
		scene._apply_params_to_world(scene.world_params)
		var n: int = scene._restore_loaded_world()
		if err != "" or n != 0 or StructureSaves.adopt_start_castle(world, 1) or not world.placed_structures().is_empty():
			printerr("FAIL structure_save_round_trip: %s: error %s, restored %d, placements %s" % [fixture, err, n, world.placed_structures()])
			fail += 1
	map_gen.params = before
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_structure_save_round_trip (castle, tower %s, walls %s)" % [anchor, walls])
	return fail
