extends "res://tests/helpers/test_helpers.gd"
## Plank bridges over water.


func _test_bridge_planks() -> int:
	## build_bridge lays one straight run of planks over generated water, with
	## land joints at the ends that touch land and tips elsewhere. The planks
	## stay when the chunk is drawn again, predict_cell sees them, they are no
	## mob home and grow no plants, the hero walks across them while plain
	## water still blocks, and a new map clears them. Land, bent runs and
	## cells that already have planks are refused.
	print("-- test_bridge_planks")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var piece := func(n: String) -> Vector2i:
		return TileCatalog.TILES["BRIDGE_PLANK_%s_WATER" % n]["atlas"]
	var want := {
		[3, true, true, true]: ["H_START", "H", "H_END"],
		[1, true, true, true]: ["H_SINGLE"],
		[2, false, false, false]: ["V_TIP_N", "V_TIP_S"],
		[3, true, true, false]: ["H_START", "H", "H_TIP_E"],
		[2, false, false, true]: ["V_TIP_N", "V_END"],
	}
	for k in want:
		var got: Array[Vector2i] = world.bridge_pieces(k[0], k[1], k[2], k[3])
		var names: Array = want[k].map(piece)
		if got != Array(names, TYPE_VECTOR2I, "", null):
			printerr("FAIL bridge_planks: pieces %s got %s, want %s" % [k, got, want[k]])
			fail += 1
	# A row of 2..6 water cells near the origin with land at both ends.
	var run_start := Vector2i(1 << 20, 0)
	var run_len := 0
	var seed_value := 0
	var land := func(c: Vector2i) -> bool:
		return world.ground_is_walkable(world.predict_cell(c)[0])
	for s in [11, 42, 7, 1, 99, 3, 5]:
		world.apply_map_params(_spawn_params(s, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell in world.get_used_cells(0):
			if not land.call(cell) or world.predict_cell(cell + Vector2i.RIGHT)[0] != TileCatalog.WATER:
				continue
			var n := 1
			while n <= 6 and world.predict_cell(cell + Vector2i(n + 1, 0))[0] == TileCatalog.WATER:
				n += 1
			if n >= 2 and n <= 6 and land.call(cell + Vector2i(n + 1, 0)) \
					and world.get_cell_source_id(0, cell + Vector2i(n + 1, 0)) != -1:
				run_start = cell + Vector2i.RIGHT
				run_len = n
				break
		if run_len > 0:
			seed_value = s
			break
	if run_len == 0:
		printerr("FAIL bridge_planks: no short water gap between land near the origin on any seed")
		scene.queue_free()
		return fail + 1
	var run_end := run_start + Vector2i(run_len - 1, 0)
	if world.build_bridge(run_start - Vector2i.RIGHT, run_end) or world.build_bridge(run_start, run_end + Vector2i.DOWN):
		printerr("FAIL bridge_planks: a run onto land or a bent run was accepted")
		fail += 1
	if not world.build_bridge(run_end, run_start) or world.build_bridge(run_start, run_start):
		printerr("FAIL bridge_planks: build_bridge %s..%s did not build exactly once" % [run_start, run_end])
		fail += 1
	world.generate_chunk(Vector2(0, 0))
	var pieces: Array[Vector2i] = world.bridge_pieces(run_len, true, true, true)
	for i in run_len:
		var c := run_start + Vector2i(i, 0)
		if world.get_cell_atlas_coords(0, c) != pieces[i] or world.predict_cell(c) != [pieces[i], world.NO_PLANT]:
			printerr("FAIL bridge_planks: %s drawn %s predicted %s, want %s" % [
				c, world.get_cell_atlas_coords(0, c), world.predict_cell(c), pieces[i]])
			fail += 1
		if not world.is_walkable_land(c) or world.get_cell_source_id(1, c) != -1 \
				or world.get_cell_source_id(world.GROUND_DECOR_LAYER, c) != -1:
			printerr("FAIL bridge_planks: %s is not bare walkable ground" % c)
			fail += 1
		if MobSpawner.is_home_cell(world, c, MobCatalog.HOME_SAND) or MobSpawner.is_home_cell(world, c, MobCatalog.HOME_GRASS):
			printerr("FAIL bridge_planks: %s is a mob home" % c)
			fail += 1
	# The hero's body walks the whole bridge; the water row next to it blocks.
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	scene.get_node("World").add_child(player)
	var free_row := func(row: Vector2i) -> bool:
		player.global_position = world.to_global(world.map_to_local(row - Vector2i.RIGHT))
		return player.move_and_collide(Vector2(16.0 * (run_len + 1), 0), true) == null
	await physics_frame
	await physics_frame
	if not free_row.call(run_start):
		printerr("FAIL bridge_planks: the hero cannot walk across the bridge")
		fail += 1
	var blocked := 0
	for side in [Vector2i.UP, Vector2i.DOWN]:
		if world.predict_cell(run_start + side)[0] == TileCatalog.WATER:
			blocked += 0 if free_row.call(run_start + side) else 1
		else:
			blocked += 1  # land there; nothing to check
	if blocked != 2 or world.predict_cell(run_start + Vector2i.DOWN)[0] != TileCatalog.WATER \
			and world.predict_cell(run_start + Vector2i.UP)[0] != TileCatalog.WATER:
		printerr("FAIL bridge_planks: the hero walks over plain water next to the bridge, or no water there")
		fail += 1
	player.queue_free()
	world.apply_map_params(_spawn_params(seed_value, 0.0))
	world.generate_chunk(Vector2(0, 0))
	if world.get_cell_atlas_coords(0, run_start) != TileCatalog.WATER:
		printerr("FAIL bridge_planks: a new map kept the bridge at %s" % run_start)
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_bridge_planks (seed %s, %s cells at %s)" % [seed_value, run_len, run_start])
	return fail
