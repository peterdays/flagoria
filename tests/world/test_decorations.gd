extends "res://tests/helpers/test_helpers.gd"
## Flowers, forest walls and decorations on the map.


func _test_flowers() -> int:
	## Flowers (atlas 9,3) need walkable land, moisture above 0, altitude in
	## (flower_min_alt, flower_max_alt] and chance above flower_min_chance.
	## Bushes and trees win where bands overlap, and turning flowers off
	## leaves every bush and tree where it was.
	print("-- test_flowers")
	const FLOWER := Vector2i(9, 3)
	const BUSH := Vector2i(7, 3)
	const NONE := Vector2i(-1, -1)
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")

	var params = _pre_biome_defaults()
	params.altitude_seed = 2
	params.moisture_seed = 7
	params.temperature_seed = 12
	params.items_seed = 17
	world.apply_map_params(params)
	var ground := Vector2i(500, 500)
	var water := Vector2i(501, 500)
	world.set_cell(0, ground, 0, Vector2i(5, 0))
	world.set_cell(0, water, 0, Vector2i(5, 6))
	# Flowers are walkable, so they must draw below the player (sprite z 0).
	if world.get_layer_z_index(world.GROUND_DECOR_LAYER) >= 0 or world.GROUND_DECOR_LAYER == 1:
		printerr("FAIL flowers: ground decor layer %s z=%s must be < 0 and not layer 1" % [world.GROUND_DECOR_LAYER, world.get_layer_z_index(world.GROUND_DECOR_LAYER)])
		fail += 1
	var L := 2
	# [name, cell, alt, moist, chance, expected layer-1 atlas, expected layer-2 atlas]
	var cases := [
		["in_band", ground, 0.28, 0.5, 0.9, NONE, FLOWER],
		["low_chance", ground, 0.28, 0.5, 0.1, NONE, NONE],
		["dry", ground, 0.28, -0.1, 0.9, NONE, NONE],
		["below_band", ground, 0.25, 0.5, 0.9, NONE, NONE],
		["bush_band", ground, 0.35, 0.5, 0.9, BUSH, NONE],
		["water", water, 0.28, 0.5, 0.9, NONE, NONE],
	]
	for c in cases:
		world.erase_cell(1, c[1])
		world.erase_cell(L, c[1])
		world.set_tile_type_z1(c[1], c[2], c[3], 0.0, c[4])
		var got1: Vector2i = world.get_cell_atlas_coords(1, c[1])
		var got2: Vector2i = world.get_cell_atlas_coords(L, c[1])
		if got1 != c[5] or got2 != c[6]:
			printerr("FAIL flowers case=%s got l1=%s l2=%s want %s %s" % [c[0], got1, got2, c[5], c[6]])
			fail += 1

	params.chunk_width = 64
	params.chunk_height = 64
	world.apply_map_params(params)
	world.generate_chunk(Vector2(0, 0))
	var with_flowers := {}
	var flowers := 0
	for x in range(-32, 32):
		for y in range(-32, 32):
			var cell := Vector2i(x, y)
			var a1: Vector2i = world.get_cell_atlas_coords(1, cell)
			var a2: Vector2i = world.get_cell_atlas_coords(L, cell)
			if a1 == FLOWER:
				printerr("FAIL flowers: flower on foliage layer 1 at %s" % cell)
				fail += 1
			with_flowers[cell] = [a1, a2]
			if a2 == FLOWER:
				flowers += 1
				if not world.is_walkable_land(cell):
					printerr("FAIL flowers: flower on non-walkable cell %s" % cell)
					fail += 1
	if flowers == 0:
		printerr("FAIL flowers: default params placed no flowers in a 64x64 chunk")
		fail += 1

	params.flower_min_chance = 1.0
	world.apply_map_params(params)
	world.generate_chunk(Vector2(0, 0))
	for cell in with_flowers.keys():
		var a1: Vector2i = world.get_cell_atlas_coords(1, cell)
		var a2: Vector2i = world.get_cell_atlas_coords(L, cell)
		if a1 != with_flowers[cell][0] or a2 != NONE:
			printerr("FAIL flowers: without flowers cell %s l1=%s l2=%s want %s %s" % [cell, a1, a2, with_flowers[cell][0], NONE])
			fail += 1
	if fail == 0:
		print("PASS test_flowers flowers=%s" % flowers)
	scene.queue_free()
	return 1 if fail > 0 else 0


func _test_forest_walls() -> int:
	## A row or column of adjacent TREE, BUSH or PINE cells is a wall: sweep the
	## player's shape across it in half-pixel lanes and require every lane to
	## stop. Half pixels matter: a gap 1 px wider than the player only opens
	## between whole-pixel lanes. With one free cell between plants the
	## player must still pass.
	print("-- test_forest_walls")
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	var body: CollisionShape2D = player.get_node("CollisionShape2D")
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body.shape
	query.collision_mask = player.collision_mask
	var offset: Vector2 = body.position
	player.free()
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var fail := 0
	for tile_name in ["TREE", "BUSH", "PINE"]:
		var tile: Vector2i = TileCatalog.TILES[tile_name]["atlas"]
		world.clear()
		for x in range(-2, 50):
			for y in range(-2, 50):
				world.set_cell(0, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
		for i in range(4, 16):
			world.set_cell(1, Vector2i(i, 10), TileCatalog.SOURCE_ID, tile)  # row
			world.set_cell(1, Vector2i(30, i), TileCatalog.SOURCE_ID, tile)  # column
		for i in range(4, 16, 2):
			world.set_cell(1, Vector2i(i, 30), TileCatalog.SOURCE_ID, tile)  # spaced row
			world.set_cell(1, Vector2i(40, i + 20), TileCatalog.SOURCE_ID, tile)  # spaced column
		await physics_frame
		await physics_frame
		var space: PhysicsDirectSpaceState2D = world.get_world_2d().direct_space_state
		var sweeps := [
			["row", Vector2i(5, 10), Vector2i(14, 10), Vector2(0, 1), true],
			["column", Vector2i(30, 5), Vector2i(30, 14), Vector2(1, 0), true],
			["spaced_row", Vector2i(5, 30), Vector2i(14, 30), Vector2(0, 1), false],
			["spaced_column", Vector2i(40, 25), Vector2i(40, 34), Vector2(1, 0), false],
		]
		for sw in sweeps:
			var a: Vector2 = world.to_global(world.map_to_local(sw[1]))
			var b: Vector2 = world.to_global(world.map_to_local(sw[2]))
			var dir: Vector2 = sw[3]
			var lanes := int((b - a).length() * 2.0)  # every 0.5 px
			var passes := 0
			for i in lanes:
				query.transform = Transform2D(0, a.lerp(b, float(i) / lanes) - dir * 40.0 + offset)
				query.motion = dir * 80.0
				if space.cast_motion(query)[0] >= 1.0:
					passes += 1
			if sw[4] and passes > 0:
				printerr("FAIL forest_walls: %s %s lets %d/%d lanes through" % [tile_name, sw[0], passes, lanes])
				fail += 1
			elif not sw[4] and passes == 0:
				printerr("FAIL forest_walls: %s %s has no gap the player fits through" % [tile_name, sw[0]])
				fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_forest_walls")
	return fail


func _test_no_decorations_on_water() -> int:
	print("-- test_no_decorations_on_water")
	var cases = [
		{"name": "char_seeds", "alt": 2, "moist": 7, "temp": 12, "items": 17, "water": 0.2, "sand": 0.25},
		{"name": "high_water", "alt": 2, "moist": 7, "temp": 12, "items": 17, "water": 0.45, "sand": 0.5},
		{"name": "seed_set_b", "alt": 99, "moist": 101, "temp": 103, "items": 107, "water": 0.2, "sand": 0.25},
		{"name": "seed_set_c_high_water", "alt": 4242, "moist": 5252, "temp": 6262, "items": 7272, "water": 0.4, "sand": 0.48},
	]
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	if world == null:
		printerr("FAIL: World/worldMap missing")
		return 1

	for case in cases:
		var params = _pre_biome_defaults()
		params.altitude_seed = case["alt"]
		params.moisture_seed = case["moist"]
		params.temperature_seed = case["temp"]
		params.items_seed = case["items"]
		params.water_max_alt = case["water"]
		params.sand_max_alt = case["sand"]
		world.apply_map_params(params)
		world.generate_chunk(Vector2(0, 0))
		var bad := 0
		var tile_pos: Vector2i = world.local_to_map(Vector2(0, 0))
		for x in range(world.chunk_width):
			for y in range(world.chunk_height):
				var cell = Vector2i(
					tile_pos.x - world.chunk_width / 2 + x,
					tile_pos.y - world.chunk_height / 2 + y
				)
				var a1: Vector2i = world.get_cell_atlas_coords(1, cell)
				if a1 == Vector2i(-1, -1):
					continue
				if not world.is_walkable_land(cell):
					bad += 1
					printerr(
						"FAIL decorations_on_water case=%s cell=%s l0=%s l1=%s"
						% [case["name"], cell, world.get_cell_atlas_coords(0, cell), a1]
					)
		if bad > 0:
			fail += 1
		else:
			print("PASS no_decorations_on_water case=%s" % case["name"])

	scene.queue_free()
	return fail
