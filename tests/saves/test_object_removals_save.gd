extends "res://tests/helpers/test_helpers.gd"
## Picked flowers and destroyed stones in world saves (world.object_changes, #198).


func _removal_scene(need_stones: bool) -> Array:
	## Stones need biomes on (PlantPicker.structure_tile). Seed 0 usually has
	## both flower and stones near spawn; seed 7 often has flowers with biomes off.
	var biome := 1.0 if need_stones else 0.0
	var seeds: Array = [0, 7, 11, 42, 49] if need_stones else [7, 11, 42, 49]
	for alt_seed in seeds:
		var scene = load("res://flagoria_main.tscn").instantiate()
		root.add_child(scene)
		scene.get_node("CanvasLayer2/MainMenu").hide()
		var world = scene.get_node("World/worldMap")
		world.set_process(false)
		var params := _spawn_params(alt_seed, biome)
		params.ensure_seeds()
		scene.world_params = params
		scene._apply_params_to_world(params)
		var flower := Vector2i.MAX
		var stones := Vector2i.MAX
		var spawn: Vector2i = world.resolve_player_spawn()
		for r in range(0, 80):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var cell := spawn + Vector2i(dx, dy)
					var top: Vector2i = world.predict_cell(cell)[1]
					if flower == Vector2i.MAX and top == TileCatalog.FLOWER:
						flower = cell
					if need_stones and stones == Vector2i.MAX and top == TileCatalog.STONES:
						stones = cell
					if flower != Vector2i.MAX and (not need_stones or stones != Vector2i.MAX):
						world.generate_chunk(world.map_to_local(flower))
						if need_stones:
							world.generate_chunk(world.map_to_local(stones))
						return [scene, world, params, flower, stones]
		scene.queue_free()
		await process_frame
	return [null, null, null, Vector2i.MAX, Vector2i.MAX]


func _decor_gone(world, cell: Vector2i) -> bool:
	world.generate_chunk(world.map_to_local(cell))
	return world.get_cell_source_id(world.GROUND_DECOR_LAYER, cell) == -1 \
			and world.get_cell_source_id(1, cell) == -1


func _test_object_removals_round_trip() -> int:
	## A picked flower and destroyed stones are written as {"removed": true},
	## stay gone when the chunk is drawn again, and survive save and load.
	print("-- test_object_removals_round_trip")
	var fail := 0
	var setup := await _removal_scene(true)
	var scene = setup[0]
	var world = setup[1]
	var params: MapGenParams = setup[2]
	var flower: Vector2i = setup[3]
	var stones: Vector2i = setup[4]
	if scene == null or flower == Vector2i.MAX or stones == Vector2i.MAX:
		printerr("FAIL object_removals_round_trip: no flower %s or stones %s" % [flower, stones])
		if scene:
			scene.queue_free()
		return 1
	if not world.pick_decor(flower) or not world.destroy_decor(stones):
		printerr("FAIL object_removals_round_trip: could not remove flower %s stones %s" % [flower, stones])
		scene.queue_free()
		return 1
	var want: Dictionary = {}
	for cell in [flower, stones]:
		var chunk := WorldSave.chunk_key(cell)
		want.get_or_add(chunk, {})[WorldSave.cell_key(cell)] = {"removed": true}
	if world.object_changes() != want:
		printerr("FAIL object_removals_round_trip: entries %s, want %s" % [world.object_changes(), want])
		fail += 1
	world.generate_chunk(world.map_to_local(flower + Vector2i(32, 0)))
	if not _decor_gone(world, flower) or not _decor_gone(world, stones):
		printerr("FAIL object_removals_round_trip: redrew flower or stones")
		fail += 1
	var saved_world := WorldSave.new(params)
	saved_world.object_changes = world.object_changes()
	var saved := MapSave.save_world(saved_world, "test_object_removals_round_trip")
	var loaded := MapSave.load_world(saved["path"])
	DirAccess.remove_absolute(saved["path"])
	if saved["error"] != "" or loaded["error"] != "":
		printerr("FAIL object_removals_round_trip: save %s load %s" % [saved["error"], loaded["error"]])
		scene.queue_free()
		return fail + 1
	scene._apply_params_to_world(params)
	var restored: int = world.restore_object_changes(loaded["world"].object_changes)
	if restored != 2 or world.object_changes() != want:
		printerr("FAIL object_removals_round_trip: restored %d entries %s want 2 and %s"
				% [restored, world.object_changes(), want])
		fail += 1
	if not _decor_gone(world, flower) or not _decor_gone(world, stones):
		printerr("FAIL object_removals_round_trip: after load flower or stones came back")
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_object_removals_round_trip (flower %s, stones %s)" % [flower, stones])
	return fail


func _test_object_removals_in_game() -> int:
	## Save through the in-game menu keeps a picked flower gone after load.
	print("-- test_object_removals_in_game")
	var fail := 0
	var setup := await _removal_scene(false)
	var scene = setup[0]
	var world = setup[1]
	var flower: Vector2i = setup[3]
	if scene == null or flower == Vector2i.MAX:
		printerr("FAIL object_removals_in_game: no flower near spawn")
		if scene:
			scene.queue_free()
		return 1
	if not world.pick_decor(flower) or not _decor_gone(world, flower):
		printerr("FAIL object_removals_in_game: pick failed at %s" % flower)
		scene.queue_free()
		return 1
	if world.object_changes().is_empty():
		printerr("FAIL object_removals_in_game: no object_changes after pick")
		scene.queue_free()
		return 1
	var menu = scene.get_node("CanvasLayer1/InGameMenu")
	var result: Dictionary = menu.save_world()
	var map_gen = root.get_node("MapGen")
	var before: MapGenParams = map_gen.params
	if result["error"] != "" or map_gen.load_map_inputs(result["path"]) != "":
		printerr("FAIL object_removals_in_game: save %s" % result["error"])
		DirAccess.remove_absolute(result["path"])
		map_gen.params = before
		scene.queue_free()
		return 1
	scene.world_params = map_gen.params.duplicate_params()
	scene._apply_params_to_world(scene.world_params)
	var restored: int = scene._restore_loaded_world()
	if restored < 1 or not _decor_gone(world, flower):
		printerr("FAIL object_removals_in_game: restored %d flower at %s gone %s"
				% [restored, flower, _decor_gone(world, flower)])
		fail += 1
	DirAccess.remove_absolute(result["path"])
	map_gen.params = before
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_object_removals_in_game (flower %s)" % flower)
	return fail