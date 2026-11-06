extends "res://tests/helpers/test_helpers.gd"
## Plank bridges in world saves (world.tile_edits, #226).


func _bridge_save_scene() -> Array:
	## The main scene on seed 7 with its params applied, no player and no
	## chunk refresh, plus a shore water cell near the spawn and the step
	## from the land it touches out over the water.
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("CanvasLayer2/MainMenu").hide()
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	var params := _spawn_params(7, 0.0)
	params.ensure_seeds()
	scene.world_params = params
	scene._apply_params_to_world(params)
	var spawn: Vector2i = world.resolve_player_spawn()
	var water := func(c: Vector2i) -> bool: return world.predict_cell(c)[0] == TileCatalog.WATER
	for r in range(0, 60):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cell := spawn + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) != r or not water.call(cell):
					continue
				for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					if world.ground_is_walkable(world.predict_cell(cell - step)[0]) and water.call(cell + step) \
							and water.call(cell + step * 2):
						return [scene, world, params, cell, step]
	return [scene, world, params, Vector2i.MAX, Vector2i.ZERO]


func _test_bridge_save_round_trip() -> int:
	## A two-plank bridge saved from the in-game menu is written as two
	## chunk-keyed tile_edits entries and nothing else. Loading the save
	## and starting it the way setup_server does lays the same pieces back
	## before any chunk is drawn, walkable once drawn; the water past the
	## bridge still regenerates from the seed. Entries that are not plank
	## pieces, planks on cells that are no longer water and bad keys are
	## dropped; an old save with no tile_edits loads with no bridges.
	print("-- test_bridge_save_round_trip")
	var fail := 0
	var setup := _bridge_save_scene()
	var scene = setup[0]
	var world = setup[1]
	var params: MapGenParams = setup[2]
	var shore: Vector2i = setup[3]
	var step: Vector2i = setup[4]
	if shore == Vector2i.MAX:
		printerr("FAIL bridge_save_round_trip: seed 7 has no shore water near the spawn")
		scene.queue_free()
		return 1
	var cells: Array[Vector2i] = [shore, shore + step]
	var past := shore + step * 2  # untouched water
	if not world.build_bridge(cells[0], cells[1]):
		printerr("FAIL bridge_save_round_trip: cannot lay a bridge on %s" % [cells])
		scene.queue_free()
		return 1
	var pieces := [world.predict_cell(cells[0])[0], world.predict_cell(cells[1])[0]]

	var map_gen = root.get_node("MapGen")
	var before: MapGenParams = map_gen.params
	var result: Dictionary = scene.get_node("CanvasLayer1/InGameMenu").save_world()
	var file = JSON.parse_string(FileAccess.get_file_as_string(result["path"])) if result["error"] == "" else null
	var edits: Dictionary = file["world"]["tile_edits"] if file is Dictionary else {}
	var written := 0
	for chunk in edits:
		for key in edits[chunk]:
			var cell = WorldSave.parse_cell(key)
			if chunk == WorldSave.chunk_key(cell) and cell in cells and edits[chunk][key].get("tile", "").begins_with("BRIDGE_PLANK_"):
				written += 1
			else:
				written -= 100
	if written != 2:
		printerr("FAIL bridge_save_round_trip: save %s wrote tile_edits %s, want the 2 cells %s" % [result["error"], edits, cells])
		fail += 1

	var load_error: String = map_gen.load_map_inputs(result["path"])
	if load_error != "":
		printerr("FAIL bridge_save_round_trip: load %s" % load_error)
		fail += 1
	scene.world_params = map_gen.params.duplicate_params()
	scene._apply_params_to_world(scene.world_params)
	var drawn_before: int = world.get_used_cells(0).size()
	var bridged_before: bool = world.has_bridge(cells[0]) or world.has_bridge(cells[1])
	var restored: int = scene._restore_loaded_world()
	if drawn_before != 0 or bridged_before or restored != 2:
		printerr("FAIL bridge_save_round_trip: restored %d (cells drawn first %d, bridge before the load %s)"
				% [restored, drawn_before, bridged_before])
		fail += 1
	for i in cells.size():
		var c := cells[i]
		var walkable: bool = world.is_clear_ground(c)  # draws the chunk
		if not world.has_bridge(c) or world.get_cell_atlas_coords(0, c) != pieces[i] or not walkable:
			printerr("FAIL bridge_save_round_trip: %s after the load: bridge %s, tile %s (want %s), walkable %s"
					% [c, world.has_bridge(c), world.get_cell_atlas_coords(0, c), pieces[i], walkable])
			fail += 1
	if world.has_bridge(past) or world.get_cell_atlas_coords(0, past) != TileCatalog.WATER:
		printerr("FAIL bridge_save_round_trip: untouched %s is %s, want generated water" % [past, world.get_cell_atlas_coords(0, past)])
		fail += 1
	DirAccess.remove_absolute(result["path"])

	# Entries a load must drop or leave to other readers.
	var land := shore - step
	var bad := {}
	bad.get_or_add(WorldSave.chunk_key(past), {})[WorldSave.cell_key(past)] = {"tile": "GRASS"}
	bad.get_or_add(WorldSave.chunk_key(land), {})[WorldSave.cell_key(land)] = {"tile": "BRIDGE_PLANK_H_WATER"}
	bad.get_or_add(WorldSave.chunk_key(shore), {})["not a cell"] = {"tile": "BRIDGE_PLANK_H_WATER"}
	bad.get_or_add(WorldSave.chunk_key(shore), {})[WorldSave.cell_key(shore)] = {"removed": true}
	bad.get_or_add(WorldSave.chunk_key(cells[1]), {})[WorldSave.cell_key(cells[1])] = {"tile": "BRIDGE_PLANK_V_WATER"}
	scene._apply_params_to_world(params)
	var kept := BridgeBuilder.from_changes(bad, world)
	var v: Vector2i = TileCatalog.BRIDGE_PLANK_V_WATER
	if kept != [[cells[1].x, cells[1].y, v.x, v.y]]:
		printerr("FAIL bridge_save_round_trip: from bad entries kept %s, want only %s" % [kept, cells[1]])
		fail += 1

	# A version 1 save (no tile_edits) still loads and starts with no bridges.
	var old_error: String = map_gen.load_map_inputs("res://tests/fixtures/world_save_v1.json")
	scene.world_params = map_gen.params.duplicate_params()
	scene._apply_params_to_world(scene.world_params)
	var old_restored: int = scene._restore_loaded_world()
	if old_error != "" or old_restored != 0 or not world.bridges_for_sync().is_empty():
		printerr("FAIL bridge_save_round_trip: v1 save: error %s, restored %d" % [old_error, old_restored])
		fail += 1
	map_gen.params = before
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_bridge_save_round_trip (bridge %s)" % [cells])
	return fail
