extends "res://tests/helpers/test_helpers.gd"
## Island falloff and archipelago shaping.


func _test_island_falloff() -> int:
	## island_radius 0 leaves altitude alone; a set radius raises the origin,
	## keeps the radius unchanged, and sinks cells past 1.5 radii to water.
	print("-- test_island_falloff")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")

	var params = _pre_biome_defaults()
	params.altitude_seed = 2
	params.moisture_seed = 7
	params.temperature_seed = 12
	params.items_seed = 17
	params.chunk_width = 64
	params.chunk_height = 64
	world.apply_map_params(params)
	if world.island_altitude(Vector2i(40, -25), 0.7) != 0.7:
		printerr("FAIL island_falloff: radius 0 changed altitude")
		fail += 1

	params.island_radius = 20
	params.island_falloff = 2.0
	world.apply_map_params(params)
	if not is_equal_approx(world.island_altitude(Vector2i(0, 0), 0.1), 2.1):
		printerr("FAIL island_falloff: origin not raised by island_falloff")
		fail += 1
	if not is_equal_approx(world.island_altitude(Vector2i(20, 0), 0.7), 0.7):
		printerr("FAIL island_falloff: altitude at the radius changed")
		fail += 1
	world.generate_chunk(Vector2(0, 0))
	var land := 0
	for x in range(-32, 32):
		for y in range(-32, 32):
			var cell := Vector2i(x, y)
			var water: bool = world.get_cell_atlas_coords(0, cell) == Vector2i(5, 6)
			if Vector2(cell).length() >= 30.0 and not water:
				printerr("FAIL island_falloff: land at %s beyond 1.5 radii" % cell)
				fail += 1
			elif not water:
				land += 1
	if land == 0:
		printerr("FAIL island_falloff: no land inside the island")
		fail += 1
	if fail == 0:
		print("PASS test_island_falloff land_cells=%s" % land)
	scene.queue_free()
	return 1 if fail > 0 else 0


func _test_archipelago() -> int:
	## archipelago_spacing 0 leaves altitude alone; with a spacing, each grid
	## square's centre is raised, the sea between neighbouring centres sinks,
	## and jittered centres stay inside their square and repeat for a seed.
	print("-- test_archipelago")
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
	if world.archipelago_altitude(Vector2i(40, -25), 0.7) != 0.7:
		printerr("FAIL archipelago: spacing 0 changed altitude")
		fail += 1

	params.archipelago_spacing = 64
	params.archipelago_island_radius = 16
	params.archipelago_jitter = 0.0
	params.island_falloff = 2.0
	world.apply_map_params(params)
	for centre in [Vector2i(32, 32), Vector2i(96, 32), Vector2i(-32, -32)]:
		if not is_equal_approx(world.archipelago_altitude(centre, 0.1), 2.1):
			printerr("FAIL archipelago: centre %s not raised by island_falloff" % centre)
			fail += 1
	if world.archipelago_altitude(Vector2i(64, 32), 0.9) > params.water_max_alt:
		printerr("FAIL archipelago: cell between two centres is not sea")
		fail += 1

	params.archipelago_jitter = 1.0
	world.apply_map_params(params)
	var first: Vector2 = world.archipelago_centre(Vector2i(3, -2))
	world.apply_map_params(params)
	if world.archipelago_centre(Vector2i(3, -2)) != first:
		printerr("FAIL archipelago: centre changed for the same seed")
		fail += 1
	for sx in range(-3, 3):
		for sy in range(-3, 3):
			var c: Vector2 = world.archipelago_centre(Vector2i(sx, sy))
			var lo := Vector2(sx, sy) * 64.0
			if c.x < lo.x or c.y < lo.y or c.x > lo.x + 64.0 or c.y > lo.y + 64.0:
				printerr("FAIL archipelago: centre %s left square %s" % [c, Vector2i(sx, sy)])
				fail += 1
	if fail == 0:
		print("PASS test_archipelago")
	scene.queue_free()
	return 1 if fail > 0 else 0


func _test_archipelago_count() -> int:
	## count/extent 0 keep prior archipelago behaviour; with both set, exactly
	## N centres are active, selection is seed-stable, and spacing 0 stays a no-op.
	print("-- test_archipelago_count")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")

	var params = _pre_biome_defaults()
	params.altitude_seed = 2
	params.moisture_seed = 7
	params.temperature_seed = 12
	params.items_seed = 17
	params.archipelago_spacing = 64
	params.archipelago_island_radius = 16
	params.archipelago_jitter = 0.0
	params.island_falloff = 2.0
	world.apply_map_params(params)
	# Prior behaviour: distant centre still raised when extent/count are 0.
	if not is_equal_approx(world.archipelago_altitude(Vector2i(96, 32), 0.1), 2.1):
		printerr("FAIL archipelago_count: extent/count 0 changed prior centre boost")
		fail += 1
	if not world.archipelago_square_active(Vector2i(5, 5)):
		printerr("FAIL archipelago_count: unbounded square should be active")
		fail += 1

	params.archipelago_world_extent = 200
	params.archipelago_island_count = 0
	world.apply_map_params(params)
	if not world.archipelago_square_active(Vector2i(0, 0)):
		printerr("FAIL archipelago_count: origin square should stay active with extent only")
		fail += 1
	if world.archipelago_square_active(Vector2i(20, 20)):
		printerr("FAIL archipelago_count: far square should be inactive with extent set")
		fail += 1

	params.archipelago_island_count = 5
	world.apply_map_params(params)
	var active: Array[Vector2i] = []
	var s: int = params.archipelago_spacing
	var e: int = params.archipelago_world_extent
	var sx0: int = int(floor(float(-e) / float(s))) - 1
	var sx1: int = int(floor(float(e) / float(s))) + 1
	for sx in range(sx0, sx1 + 1):
		for sy in range(sx0, sx1 + 1):
			var sq := Vector2i(sx, sy)
			if world.archipelago_square_active(sq):
				active.append(sq)
	if active.size() != 5:
		printerr("FAIL archipelago_count: expected 5 active centres, got %s" % active.size())
		fail += 1
	for sq in active:
		var centre_cell := Vector2i(
			int(floor((float(sq.x) + 0.5) * float(s))),
			int(floor((float(sq.y) + 0.5) * float(s)))
		)
		if not is_equal_approx(world.archipelago_altitude(centre_cell, 0.1), 2.1):
			printerr("FAIL archipelago_count: active centre %s not raised" % sq)
			fail += 1
	# A candidate square inside the extent that was not selected must not raise.
	var skipped: Variant = null
	for sx in range(sx0, sx1 + 1):
		for sy in range(sx0, sx1 + 1):
			var sq2 := Vector2i(sx, sy)
			var min_x: int = sq2.x * s
			var max_x: int = (sq2.x + 1) * s - 1
			var min_y: int = sq2.y * s
			var max_y: int = (sq2.y + 1) * s - 1
			if min_x <= e and max_x >= -e and min_y <= e and max_y >= -e:
				if not world.archipelago_square_active(sq2):
					skipped = sq2
					break
		if skipped != null:
			break
	if skipped == null:
		printerr("FAIL archipelago_count: no unselected candidate inside extent")
		fail += 1
	else:
		var skipped_cell := Vector2i(
			int(floor((float(skipped.x) + 0.5) * float(s))),
			int(floor((float(skipped.y) + 0.5) * float(s)))
		)
		if is_equal_approx(world.archipelago_altitude(skipped_cell, 0.1), 2.1):
			printerr("FAIL archipelago_count: unselected centre %s still fully raised" % skipped)
			fail += 1

	var first_active: Array = active.duplicate()
	world.apply_map_params(params)
	for sq3 in first_active:
		if not world.archipelago_square_active(sq3):
			printerr("FAIL archipelago_count: active set changed for the same seed")
			fail += 1
			break

	params.archipelago_spacing = 0
	world.apply_map_params(params)
	if world.archipelago_altitude(Vector2i(40, -25), 0.7) != 0.7:
		printerr("FAIL archipelago_count: spacing 0 changed altitude")
		fail += 1
	if world.archipelago_square_active(Vector2i(0, 0)):
		printerr("FAIL archipelago_count: spacing 0 should activate no squares")
		fail += 1

	if fail == 0:
		print("PASS test_archipelago_count")
	scene.queue_free()
	return 1 if fail > 0 else 0


func _test_archipelago_count_land_masses() -> int:
	## archipelago_island_count works without archipelago_world_extent, the
	## spawn square is always kept, dropped squares are sea, and the number of
	## land masses grows with the count.
	print("-- test_archipelago_count_land_masses")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var params = _pre_biome_defaults()
	params.altitude_seed = 42
	params.moisture_seed = 7
	params.temperature_seed = 12
	params.items_seed = 17
	params.archipelago_spacing = 40
	params.archipelago_island_radius = 14
	params.island_falloff = 2.0
	var half := 120
	var previous := -1
	for count in [1, 2, 3, 4, 5, 6]:
		params.archipelago_island_count = count
		world.apply_map_params(params)
		var kept := 0
		for sx in range(-half / 40, half / 40):
			for sy in range(-half / 40, half / 40):
				var sq := Vector2i(sx, sy)
				if world.archipelago_square_active(sq):
					kept += 1
					continue
				for x in range(sx * 40, sx * 40 + 40, 3):
					for y in range(sy * 40, sy * 40 + 40, 3):
						var cell := Vector2i(x, y)
						if world.archipelago_altitude(cell, 1.0) > world.water_max_alt:
							printerr("FAIL archipelago_count_land_masses count=%s dropped square %s has land" % [count, sq])
							fail += 1
							break
					if fail > 0:
						break
		if kept != count:
			printerr("FAIL archipelago_count_land_masses count=%s kept %s squares" % [count, kept])
			fail += 1
		if not world.archipelago_square_active(Vector2i.ZERO):
			printerr("FAIL archipelago_count_land_masses count=%s dropped the spawn square" % count)
			fail += 1
		var centre := Vector2i(world.archipelago_centre(Vector2i.ZERO).round())
		if world.archipelago_altitude(centre, 0.0) <= world.water_max_alt:
			printerr("FAIL archipelago_count_land_masses count=%s spawn island is sea" % count)
			fail += 1
		var masses := _archipelago_land_masses(world, half)
		if masses < previous:
			printerr("FAIL archipelago_count_land_masses count=%s gave %s land masses, fewer than %s" % [count, masses, previous])
			fail += 1
		print("archipelago_count_land_masses count=%s masses=%s" % [count, masses])
		previous = masses
	if previous <= 1:
		printerr("FAIL archipelago_count_land_masses count=6 gave %s land masses" % previous)
		fail += 1
	if fail == 0:
		print("PASS test_archipelago_count_land_masses")
	scene.queue_free()
	return 1 if fail > 0 else 0
