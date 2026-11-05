extends "res://tests/helpers/test_helpers.gd"
## Start castle fits on a fixed seed set at default Map Settings (#371).


func _test_start_castle_fits_default_seeds() -> int:
	## Every seed in 1..200 plus the #371 known misses places a castle whose
	## gate front reaches SPAWN_MIN_REACHABLE clear cells. Time cost: about
	## 25–35 s alone with --only=start_castle_fits_default_seeds (mostly the
	## seeds that used to miss; a hit is ~30–150 ms).
	print("-- test_start_castle_fits_default_seeds")
	var seeds: Array[int] = []
	for s in range(1, 201):
		seeds.append(s)
	for s in [256, 999, 3141592, 8675309]:
		if s not in seeds:
			seeds.append(s)
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var castle: Structure = StartCastle.structure()
	var fail := 0
	var misses: Array[int] = []
	var t0 := Time.get_ticks_msec()
	for seed_value in seeds:
		var params := MapGenParams.make_defaults()
		params.altitude_seed = seed_value
		params.moisture_seed = seed_value
		params.temperature_seed = seed_value
		params.items_seed = seed_value
		params.biome_seed = seed_value
		world.apply_map_params(params)
		var spawn: Vector2i = SpawnFinder.resolve_player_spawn(world)
		var anchor: Variant = StartCastle.find_anchor(world, castle, spawn)
		if anchor == null:
			printerr("FAIL start_castle_fits_default_seeds: seed %s no fit within SEARCH_RADIUS=%s"
					% [seed_value, StartCastle.SEARCH_RADIUS])
			fail += 1
			misses.append(seed_value)
			continue
		var front: Vector2i = anchor + StartCastle.GATE_FRONT
		var foot := StructurePlacer.footprint(castle, anchor)
		var reach: int = SpawnFinder.reachable_clear_cells(
				world, front, SpawnFinder.SPAWN_MIN_REACHABLE, foot).size()
		if reach < SpawnFinder.SPAWN_MIN_REACHABLE:
			printerr("FAIL start_castle_fits_default_seeds: seed %s gate reaches %s, want %s"
					% [seed_value, reach, SpawnFinder.SPAWN_MIN_REACHABLE])
			fail += 1
			misses.append(seed_value)
	var ms := Time.get_ticks_msec() - t0
	print("start_castle_fits_default_seeds: checked %s seeds in %s ms, misses %s"
			% [seeds.size(), ms, misses])
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_start_castle_fits_default_seeds")
	return fail
