extends SceneTree
## Headless test entry point for CI.
## Run: godot --headless --path . --script res://tests/run_tests.gd
## Exit 0 on success, 1 on failure.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := 0
	failures += _test_smoke_true()
	failures += _test_map_characterization()
	failures += _test_spawn_on_land()
	failures += _test_map_settings_water_reopen()
	failures += _test_no_decorations_on_water()
	failures += await _test_water_blocks_player()
	if failures == 0:
		print("All tests passed.")
		quit(0)
	else:
		print("Tests failed: %s" % failures)
		quit(1)


func _test_smoke_true() -> int:
	## Trivial sanity check that the headless runner executes and reports.
	print("-- test_smoke_true")
	if true:
		print("PASS test_smoke_true")
		return 0
	printerr("FAIL test_smoke_true")
	return 1


func _test_map_characterization() -> int:
	## Fixed MapGenParams seeds + generate_chunk; compare atlas coords on layers 0 and 1.
	print("-- test_map_characterization")
	const CHUNK_POS := Vector2(0, 0)

	# cell -> [layer0 atlas, layer1 atlas]  (Vector2i(-1,-1) = empty)
	var expected := {
		Vector2i(-16, -16): [Vector2i(5, 6), Vector2i(-1, -1)],
		Vector2i(12, 6): [Vector2i(5, 4), Vector2i(-1, -1)],
		Vector2i(13, 6): [Vector2i(5, 1), Vector2i(-1, -1)],
		Vector2i(14, 6): [Vector2i(5, 0), Vector2i(-1, -1)],
		Vector2i(14, 11): [Vector2i(6, 0), Vector2i(-1, -1)],
		Vector2i(14, 7): [Vector2i(5, 1), Vector2i(7, 3)],
		Vector2i(0, 0): [Vector2i(5, 6), Vector2i(-1, -1)],
		Vector2i(8, -8): [Vector2i(5, 6), Vector2i(-1, -1)],
		Vector2i(-8, 8): [Vector2i(5, 6), Vector2i(-1, -1)],
		Vector2i(15, 15): [Vector2i(5, 4), Vector2i(-1, -1)],
		Vector2i(15, 6): [Vector2i(6, 0), Vector2i(7, 3)],
	}

	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	if world == null:
		printerr("FAIL: World/worldMap missing")
		return 1

	var params = MapGenParams.make_defaults()
	params.altitude_seed = 2
	params.moisture_seed = 7
	params.temperature_seed = 12
	params.items_seed = 17
	world.apply_map_params(params)
	world.generate_chunk(CHUNK_POS)

	var fail := 0
	for cell in expected.keys():
		var want = expected[cell]
		var got0: Vector2i = world.get_cell_atlas_coords(0, cell)
		var got1: Vector2i = world.get_cell_atlas_coords(1, cell)
		if got0 != want[0] or got1 != want[1]:
			printerr(
				"FAIL cell=%s expected l0=%s l1=%s got l0=%s l1=%s"
				% [cell, want[0], want[1], got0, got1]
			)
			fail += 1

	if fail == 0:
		print("PASS test_map_characterization (%s cells)" % expected.size())
	scene.queue_free()
	return fail

func _test_spawn_on_land() -> int:
	print("-- test_spawn_on_land")
	var cases = [
		{"name": "default_seeds", "alt": 2, "moist": 7, "temp": 12, "items": 17, "water": 0.2, "sand": 0.25},
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
		var params = MapGenParams.make_defaults()
		params.altitude_seed = case["alt"]
		params.moisture_seed = case["moist"]
		params.temperature_seed = case["temp"]
		params.items_seed = case["items"]
		params.water_max_alt = case["water"]
		params.sand_max_alt = case["sand"]
		world.apply_map_params(params)
		var cell: Vector2i = world.resolve_player_spawn()
		if not world.is_walkable_land(cell):
			printerr("FAIL spawn_on_land case=%s cell=%s not walkable land" % [case["name"], cell])
			fail += 1
			continue
		var neighbors: int = world.count_walkable_neighbors(cell)
		if neighbors < 1:
			printerr(
				"FAIL spawn_on_land case=%s cell=%s has zero walkable neighbors"
				% [case["name"], cell]
			)
			fail += 1
			continue
		world.apply_map_params(params)
		var again: Vector2i = world.resolve_player_spawn()
		if again != cell:
			printerr(
				"FAIL spawn_on_land case=%s nondeterministic first=%s second=%s"
				% [case["name"], cell, again]
			)
			fail += 1
			continue
		print("PASS spawn_on_land case=%s cell=%s neighbors=%s" % [case["name"], cell, neighbors])

	scene.queue_free()
	return fail

func _test_map_settings_water_reopen() -> int:
	## Map Settings must show the in-use water value on reopen, even when a
	## SpinBox LineEdit still holds a dirty string for the same numeric value.
	print("-- test_map_settings_water_reopen")
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	var spin: SpinBox = panel._spin_boxes["water_max_alt"]
	var in_use := 0.45
	spin.value = in_use
	spin.get_line_edit().text = "0.2"
	var params = MapGenParams.make_defaults()
	params.water_max_alt = in_use
	panel.load_from_params(params)
	var shown := float(spin.get_line_edit().text)
	panel.queue_free()
	if abs(shown - in_use) > 0.001:
		printerr(
			"FAIL map_settings_water_reopen shown=%s want in-use=%s"
			% [shown, in_use]
		)
		return 1
	print("PASS test_map_settings_water_reopen shown=%s" % shown)
	return 0

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
		var params = MapGenParams.make_defaults()
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

func _test_water_blocks_player() -> int:
	## A player body centred on any cell that is_walkable_land rejects must
	## overlap that cell's own collision. TileMap bodies join the physics
	## space on the next physics frame, hence the await.
	print("-- test_water_blocks_player")
	var cases = [
		{"name": "default_seeds", "alt": 2, "moist": 7, "temp": 12, "items": 17, "water": 0.2, "sand": 0.25},
		{"name": "high_water", "alt": 2, "moist": 7, "temp": 12, "items": 17, "water": 0.45, "sand": 0.5},
		{"name": "seed_set_c_high_water", "alt": 4242, "moist": 5252, "temp": 6262, "items": 7272, "water": 0.4, "sand": 0.48},
	]
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	var player_shape: CollisionShape2D = player.get_node("CollisionShape2D")
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = player_shape.shape
	query.collision_mask = player.collision_mask
	var shape_offset: Vector2 = player_shape.position
	player.free()

	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var space: PhysicsDirectSpaceState2D = world.get_world_2d().direct_space_state

	for case in cases:
		var params = MapGenParams.make_defaults()
		params.altitude_seed = case["alt"]
		params.moisture_seed = case["moist"]
		params.temperature_seed = case["temp"]
		params.items_seed = case["items"]
		params.water_max_alt = case["water"]
		params.sand_max_alt = case["sand"]
		world.apply_map_params(params)
		world.generate_chunk(Vector2(0, 0))
		await physics_frame
		var checked := 0
		var open := 0
		for cell in world.get_used_cells(0):
			if world.is_walkable_land(cell):
				continue
			checked += 1
			query.transform = Transform2D(0.0, world.map_to_local(cell) + shape_offset)
			var blocked := false
			for hit in space.intersect_shape(query, 32):
				if hit["collider"] == world and world.get_coords_for_body_rid(hit["rid"]) == cell:
					blocked = true
					break
			if not blocked:
				open += 1
				if open <= 3:
					printerr("FAIL water_blocks_player case=%s cell=%s is open" % [case["name"], cell])
		if checked == 0 or open > 0:
			printerr(
				"FAIL water_blocks_player case=%s checked=%s open=%s"
				% [case["name"], checked, open]
			)
			fail += 1
		else:
			print("PASS water_blocks_player case=%s checked=%s" % [case["name"], checked])

	scene.queue_free()
	return fail

