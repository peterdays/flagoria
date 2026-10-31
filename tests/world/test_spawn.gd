extends "res://tests/helpers/test_helpers.gd"
## Player spawn on reachable land (Scripts/world/spawn_finder.gd resolve_player_spawn).


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
		var params = _pre_biome_defaults()
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


func _test_spawn_reachable() -> int:
	## The spawn cell is clear ground (no tree, bush or stones) and the player
	## can walk from it to at least SPAWN_MIN_REACHABLE clear cells. Seed 7 with
	## biomes on used to spawn on a single sand cell surrounded by water.
	print("-- test_spawn_reachable")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var need: int = world.SPAWN_MIN_REACHABLE
	var cases := [[7, 0.003]]
	for biome_frequency in [0.003, 0.0]:
		for seed_value in range(1, 51):
			cases.append([seed_value, biome_frequency])
	var fail := 0
	for case in cases:
		world.apply_map_params(_spawn_params(case[0], case[1]))
		var cell: Vector2i = world.resolve_player_spawn()
		var label := "seed=%s biomes=%s cell=%s" % [case[0], case[1] > 0.0, cell]
		if not world.is_clear_ground(cell):
			printerr("FAIL spawn_reachable %s is not clear ground" % label)
			fail += 1
			continue
		var reach: int = world.reachable_clear_cells(cell, need).size()
		if reach < need:
			printerr("FAIL spawn_reachable %s reaches %s cells, need %s" % [label, reach, need])
			fail += 1
	if fail == 0:
		print("PASS test_spawn_reachable (%s maps, %s+ cells each)" % [cases.size(), need])
	scene.queue_free()
	return fail


func _test_spawn_radius_no_overlap() -> int:
	## Six players joining at once, then all respawning at once (and again
	## while half stand around the spawn) each get a spot: clear walkable
	## ground, within SPAWN_RADIUS of the spawn point, and no two collision
	## boxes overlap.
	print("-- test_spawn_radius_no_overlap")
	var fail := 0
	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var radius: float = world.SPAWN_RADIUS
	for seed_value in [11, 42, 99]:
		world.apply_map_params(_spawn_params(seed_value, 0.003))
		var cell: Vector2i = world.resolve_player_spawn()
		var origin: Vector2 = world.map_to_local(cell)
		var players: Array = []
		for peer_id in range(2, 8):
			scene.add_player(peer_id)
			players.append(scene.get_node("World/%s" % peer_id))
		var check := func(stage: String) -> int:
			var bad := 0
			for i in players.size():
				var p = players[i]
				var label := "seed=%s %s player %s at %s" % [seed_value, stage, p.name, p.position]
				if not world.is_clear_ground(world.local_to_map(p.position)):
					printerr("FAIL spawn_radius %s not on clear walkable ground" % label)
					bad += 1
				if p.position.distance_to(origin) > radius:
					printerr("FAIL spawn_radius %s is %s px from the spawn, radius %s" % [label, p.position.distance_to(origin), radius])
					bad += 1
				var box: Rect2 = _body_rect(p)
				for j in range(i + 1, players.size()):
					if box.intersects(_body_rect(players[j])):
						printerr("FAIL spawn_radius %s overlaps player %s at %s" % [label, players[j].name, players[j].position])
						bad += 1
			return bad
		fail += check.call("join")
		var joined: Array[Vector2] = []
		for p in players:
			joined.append(p.position)
		if players[0].position != origin:
			printerr("FAIL spawn_radius seed=%s first player at %s, not the spawn %s" % [seed_value, players[0].position, origin])
			fail += 1
		# Everyone dies on the same spot and respawns on the same frame.
		for p in players:
			p.health.set_health_now(0)
			p.position = origin
		for p in players:
			p.health.respawn()
		fail += check.call("respawn all")
		var respawned: Array[Vector2] = []
		for p in players:
			respawned.append(p.position)
		if respawned != joined:
			printerr("FAIL spawn_radius seed=%s respawn spots %s differ from join spots %s" % [seed_value, respawned, joined])
			fail += 1
		# Half die and respawn while the others still stand on the first spots.
		for i in range(0, players.size(), 2):
			players[i].health.set_health_now(0)
		for i in range(0, players.size(), 2):
			players[i].health.respawn()
		fail += check.call("respawn half")
		for p in players:
			p.free()
		if fail == 0:
			print("PASS spawn_radius seed=%s spawn=%s spots=%s" % [seed_value, cell, joined])

	scene.queue_free()
	if fail == 0:
		print("PASS test_spawn_radius_no_overlap")
	return fail


func _test_spawn_full_area_searches_outward() -> int:
	## With every spot in the radius taken, a player gets the nearest free
	## spot beyond it; with every spot of the usual search taken too, the
	## search keeps going outward to a free spot instead of the spawn point.
	print("-- test_spawn_full_area_searches_outward")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	world.apply_map_params(_spawn_params(42, 0.003))
	var cell: Vector2i = world.resolve_player_spawn()
	var origin: Vector2 = world.map_to_local(cell)
	var spots: Array[Vector2] = world.spawn_spots(cell)
	var inside: Array[Vector2] = []
	var outside := Vector2.INF
	for spot in spots:
		if spot.distance_to(origin) <= world.SPAWN_RADIUS:
			inside.append(spot)
		elif outside == Vector2.INF:
			outside = spot
	var full_radius: Vector2 = world.free_spawn_position(cell, inside)
	if full_radius != outside or full_radius.distance_to(origin) <= world.SPAWN_RADIUS:
		printerr("FAIL spawn_full_area full radius -> %s, want nearest outside %s" % [full_radius, outside])
		fail += 1
	# Every spot the usual search walks is taken: the next one out is free.
	var beyond: Array[Vector2] = world.spawn_spots(cell, spots.size() * 4)
	var want := Vector2.INF
	for spot in beyond:
		if spot not in spots:
			want = spot
			break
	var all_taken: Vector2 = world.free_spawn_position(cell, spots)
	if all_taken != want or all_taken == origin or not world.is_clear_ground(world.local_to_map(all_taken)):
		printerr("FAIL spawn_full_area %s spots taken -> %s, want the next free spot %s (spawn %s)"
				% [spots.size(), all_taken, want, origin])
		fail += 1
	scene.queue_free()
	if fail == 0:
		print("PASS test_spawn_full_area_searches_outward (%s in radius, next free %s)" % [inside.size(), all_taken])
	return fail


func _test_spawn_late_join() -> int:
	## Peers joining one by one, each its own process: every joiner stands on
	## the spot the server picked for it once the map arrives, and no two
	## players overlap. (A client used to place its own player from its stale
	## copies of the others, and the owner's position wins.) Then every player
	## dies in one frame and the server sends the batch to spots apart, where
	## each then stands.
	## Once on a dedicated server with four joiners, once on a listen host
	## with three.
	print("-- test_spawn_late_join")
	var fail := 0
	await process_frame
	fail += await _spawn_session("dedicated", 4)
	fail += await _spawn_session("host", 3)
	if fail == 0:
		print("PASS test_spawn_late_join")
	return fail
