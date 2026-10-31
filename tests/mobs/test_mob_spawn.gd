extends "res://tests/helpers/test_helpers.gd"
## Mob placement, spawn rate, wandering and sprite sheets (Scripts/mob_spawner.gd, Scripts/mob.gd).


func _test_mob_predict_matches_chunks() -> int:
	## TileMap.predict_cell gives the same ground and plant/structure as
	## generate_chunk, with biomes off, on, and archipelago, so mobs can read
	## terrain where no chunk was generated.
	print("-- test_mob_predict_matches_chunks")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var cases := [_spawn_params(11, 0.0), _spawn_params(42, 0.003), _biome_terrain_params(true)]
	var fail := 0
	for i in cases.size():
		world.apply_map_params(cases[i])
		world.generate_chunk(Vector2(0, 0))
		var checked := 0
		for cell in world.get_used_cells(0):
			var top: Vector2i = world.get_cell_atlas_coords(1, cell)
			if top == world.NO_PLANT:
				top = world.get_cell_atlas_coords(2, cell)
			var want := [world.get_cell_atlas_coords(0, cell), top]
			var got: Array = world.predict_cell(cell)
			checked += 1
			if got != want:
				printerr("FAIL mob_predict case=%s cell=%s predicted %s, chunk has %s" % [i, cell, got, want])
				fail += 1
				break
			if world.predicted_clear(cell) != world.is_clear_ground(cell):
				printerr("FAIL mob_predict case=%s cell=%s predicted_clear differs" % [i, cell])
				fail += 1
				break
		if checked == 0:
			printerr("FAIL mob_predict case=%s generated no cells" % i)
			fail += 1
	if fail == 0:
		print("PASS test_mob_predict_matches_chunks (%s maps)" % cases.size())
	scene.queue_free()
	return fail


func _test_mob_plan() -> int:
	## Mob placement is the same for a seed, places a few mobs on home ground
	## (crabs on sand, the rest on grass) away from the player spawn and apart
	## from each other, and generates no tiles.
	print("-- test_mob_plan")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var fail := 0
	var total := 0
	for biome_frequency in [0.0, 0.003]:
		for seed_value in [1, 7, 11, 42, 99]:
			var label := "seed=%s biomes=%s" % [seed_value, biome_frequency > 0.0]
			world.apply_map_params(_spawn_params(seed_value, biome_frequency))
			var plan: Array = MobSpawner.plan(world, Vector2i(0, 0), seed_value)
			if world.get_used_cells(0).size() != 0:
				printerr("FAIL mob_plan %s planning generated tiles" % label)
				fail += 1
			world.apply_map_params(_spawn_params(seed_value, biome_frequency))
			if MobSpawner.plan(world, Vector2i(0, 0), seed_value) != plan:
				printerr("FAIL mob_plan %s differs between runs" % label)
				fail += 1
			if plan.size() > MobSpawner.MAX_MOBS:
				printerr("FAIL mob_plan %s has %s mobs, cap %s" % [label, plan.size(), MobSpawner.MAX_MOBS])
				fail += 1
			total += plan.size()
			for i in plan.size():
				var cell: Vector2i = plan[i]["cell"]
				var type: String = plan[i]["type"]
				var home: int = MobCatalog.stat(type, "home")
				if not MobSpawner.is_home_cell(world, cell, home):
					printerr("FAIL mob_plan %s %s at %s is not on its home ground" % [label, type, cell])
					fail += 1
				if maxi(absi(cell.x), absi(cell.y)) <= MobSpawner.SAFE_RADIUS:
					printerr("FAIL mob_plan %s %s at %s is next to the spawn" % [label, type, cell])
					fail += 1
				for j in i:
					var o: Vector2i = plan[j]["cell"]
					if maxi(absi(cell.x - o.x), absi(cell.y - o.y)) < MobSpawner.MIN_GAP:
						printerr("FAIL mob_plan %s mobs %s and %s are too close" % [label, i, j])
						fail += 1
	if total == 0:
		printerr("FAIL mob_plan no mobs on any map")
		fail += 1
	if fail == 0:
		print("PASS test_mob_plan (%s mobs over 10 maps)" % total)
	scene.queue_free()
	return fail


func _test_mob_spawn_rate() -> int:
	## The host's saved mob spawn rate: defaults above the old 1x, the menu
	## slider saves it and it reloads, it changes how many mobs a world gets,
	## and a client never spawns mobs from its own rate.
	print("-- test_mob_spawn_rate")
	var fail := 0
	var game = root.get_node("GameSettings")
	var saved_path: String = game.save_path
	game.save_path = "user://test_game_settings.cfg"
	DirAccess.remove_absolute(game.save_path)
	game.load_from_disk()
	if game.mob_rate != game.MOB_RATE_DEFAULT or game.MOB_RATE_DEFAULT <= 1.0:
		printerr("FAIL mob_spawn_rate: fresh rate %s, default %s (must be above 1x)" % [game.mob_rate, game.MOB_RATE_DEFAULT])
		fail += 1
	# Corrupt or hand-edited values: default or clamp, never a crash.
	for pair in [["abc", 2.0], [NAN, 2.0], [INF, 2.0], [-1, 0.5], [9, 3.0], [1.1, 1.0]]:
		var cfg := ConfigFile.new()
		cfg.set_value(game.SECTION, "mob_rate", pair[0])
		cfg.save(game.save_path)
		game.load_from_disk()
		if not is_equal_approx(game.mob_rate, pair[1]):
			printerr("FAIL mob_spawn_rate: saved %s loads as %s, want %s" % [pair[0], game.mob_rate, pair[1]])
			fail += 1
	DirAccess.remove_absolute(game.save_path)
	game.load_from_disk()

	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu = scene.get_node("CanvasLayer2/MainMenu")
	if not is_equal_approx(menu.mob_rate.value, game.MOB_RATE_DEFAULT) or menu.mob_rate_value.text != "2x":
		printerr("FAIL mob_spawn_rate: slider starts at %s (%s)" % [menu.mob_rate.value, menu.mob_rate_value.text])
		fail += 1
	menu.mob_rate.value = 0.75
	if menu.mob_rate_value.text != "0.75x":
		printerr("FAIL mob_spawn_rate: label shows %s at 0.75" % menu.mob_rate_value.text)
		fail += 1
	game.mob_rate = game.MOB_RATE_DEFAULT  # reload from disk, as on the next launch
	game.load_from_disk()
	if not is_equal_approx(game.mob_rate, 0.75):
		printerr("FAIL mob_spawn_rate: slider at 0.75 reloads as %s" % game.mob_rate)
		fail += 1

	# The host spawns more mobs at a higher rate, within that rate's cap.
	var world = scene.get_node("World/worldMap")
	var mobs_node: MobSpawner = scene.get_node("World/Mobs")
	var want_caps := {1.0: [300, 3, 10], 2.0: [150, 6, 20], 3.0: [100, 9, 30]}
	for rate in want_caps:
		var c: Dictionary = MobSpawner.caps(rate)
		if [c["cells_per_mob"], c["per_island"], c["total"]] != want_caps[rate]:
			printerr("FAIL mob_spawn_rate: caps at %sx are %s, want %s" % [rate, c, want_caps[rate]])
			fail += 1
	var counts := {}
	var most := 0
	for rate in [1.0, game.MOB_RATE_DEFAULT, game.MOB_RATE_MAX]:
		game.set_mob_rate(rate, false)
		counts[rate] = 0
		for seed_value in [1, 7, 42]:
			scene.world_params = _spawn_params(seed_value, 0.003)
			world.apply_map_params(scene.world_params)
			var n: int = scene.spawn_mobs()
			if n != mobs_node.mobs().size() or n > MobSpawner.caps(rate)["total"]:
				printerr("FAIL mob_spawn_rate: rate %s seed %s spawned %s, %s in the tree" % [rate, seed_value, n, mobs_node.mobs().size()])
				fail += 1
			counts[rate] += n
			most = maxi(most, n)
	if not (counts[game.MOB_RATE_DEFAULT] >= counts[1.0] * 3 / 2 and counts[game.MOB_RATE_MAX] > counts[game.MOB_RATE_DEFAULT]):
		printerr("FAIL mob_spawn_rate: mobs over 3 maps by rate %s" % counts)
		fail += 1
	if most <= MobSpawner.MAX_MOBS:
		printerr("FAIL mob_spawn_rate: no map got more than the 1x cap of %s mobs" % MobSpawner.MAX_MOBS)
		fail += 1

	# A client with its own rate spawns nothing; it only gets the host's mobs.
	mobs_node.clear_mobs()
	var cmp := SceneMultiplayer.new()
	set_multiplayer(cmp, scene.get_path())
	var cpeer := ENetMultiplayerPeer.new()
	cpeer.create_client("127.0.0.1", _free_udp_port())
	cmp.multiplayer_peer = cpeer
	game.set_mob_rate(game.MOB_RATE_MAX, false)
	var client_count: int = scene.spawn_mobs()
	if client_count != 0 or mobs_node.mobs().size() != 0:
		printerr("FAIL mob_spawn_rate: client spawned %s mobs (%s in the tree)" % [client_count, mobs_node.mobs().size()])
		fail += 1
	cpeer.close()
	set_multiplayer(null, scene.get_path())

	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(game.save_path)
	game.save_path = saved_path
	game.load_from_disk()
	if fail == 0:
		print("PASS test_mob_spawn_rate (mobs over 3 maps by rate %s)" % counts)
	return fail


func _test_mob_wander() -> int:
	## Offline host: spawn the map's mobs, run 40 s of wander, and check every
	## mob moves, never leaves its home ground or wander radius, and shows the
	## walk or idle rows for its facing.
	print("-- test_mob_wander")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var mobs_node: MobSpawner = scene.get_node("World/Mobs")
	scene.world_params = _spawn_params(42, 0.003)
	world.apply_map_params(scene.world_params)
	var fail := 0
	var count: int = scene.spawn_mobs()
	var mobs: Array = mobs_node.mobs()
	if count == 0 or mobs.size() != count:
		printerr("FAIL mob_wander spawned %s, %s in the tree" % [count, mobs.size()])
		scene.queue_free()
		return 1
	var start := {}
	for m in mobs:
		start[m] = m.position
	var moved := {}
	var dt := 1.0 / 45.0
	for tick in range(45 * 40):
		for m in mobs:
			m.think(dt)
			m._process(dt)
			if m.position != start[m]:
				moved[m] = true
			var cell: Vector2i = world.local_to_map(m.position)
			if not MobSpawner.is_home_cell(world, cell, MobCatalog.stat(m.mob_type, "home")):
				printerr("FAIL mob_wander %s %s left home ground at %s" % [m.name, m.mob_type, cell])
				fail += 1
			if m.position.distance_to(m.home) > Mob.WANDER_RADIUS + 0.01:
				printerr("FAIL mob_wander %s left its wander radius" % m.name)
				fail += 1
			var row: int = m.sprite.frame_coords.y
			var block: int = MobCatalog.ANIMS[m.anim_name()]["row"]
			if row != block + m.facing:
				printerr("FAIL mob_wander %s shows row %s for %s facing %s" % [m.name, row, m.anim_name(), m.facing])
				fail += 1
		if fail > 0:
			break
	if fail == 0 and moved.size() != mobs.size():
		printerr("FAIL mob_wander only %s of %s mobs moved" % [moved.size(), mobs.size()])
		fail += 1
	if fail == 0:
		print("PASS test_mob_wander (%s mobs)" % mobs.size())
	scene.queue_free()
	return fail


func _test_mob_sheet_swap() -> int:
	## Each mob type's art is one sheet path: the scene holds no texture and the
	## sprite uses whatever file that path names, on the shared 8x16 grid.
	print("-- test_mob_sheet_swap")
	var fail := 0
	var tscn := FileAccess.get_file_as_string("res://Mobs/mob.tscn")
	if tscn.contains(".png"):
		printerr("FAIL mob_sheet_swap Mobs/mob.tscn names a texture")
		fail += 1
	for type in MobCatalog.names():
		var mob: Mob = load("res://Mobs/mob.tscn").instantiate()
		mob.setup(type, Vector2.ZERO, 1)
		root.add_child(mob)
		var tex: Texture2D = mob.sprite.texture
		var want: String = MobCatalog.stat(type, "sheet")
		if tex == null or tex.resource_path != want:
			printerr("FAIL mob_sheet_swap %s sprite is not %s" % [type, want])
			fail += 1
		elif tex.get_size() != Vector2(MobCatalog.SHEET_COLS, MobCatalog.SHEET_ROWS) * MobCatalog.FRAME_SIZE:
			printerr("FAIL mob_sheet_swap %s sheet is %s" % [type, tex.get_size()])
			fail += 1
		if mob.sprite.hframes != MobCatalog.SHEET_COLS or mob.sprite.vframes != MobCatalog.SHEET_ROWS:
			printerr("FAIL mob_sheet_swap %s sprite grid is not 8x16" % type)
			fail += 1
		mob.queue_free()
	if fail == 0:
		print("PASS test_mob_sheet_swap (%s types)" % MobCatalog.names().size())
	return fail
