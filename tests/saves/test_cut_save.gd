extends "res://tests/helpers/test_helpers.gd"
## Tree and bush cuts in world saves (world.object_changes, #198).


func _cut_save_scene() -> Array:
	## The main scene on seed 7 with its params applied, no player and no
	## chunk refresh, plus the nearest generated tree and bush to the spawn.
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("CanvasLayer2/MainMenu").hide()
	var world = scene.get_node("World/worldMap")
	world.set_process(false)  # the test steps play_time and draws chunks itself
	var params := _spawn_params(7, 0.0)
	params.ensure_seeds()
	scene.world_params = params
	scene._apply_params_to_world(params)
	var found := {}
	var spawn: Vector2i = world.resolve_player_spawn()
	for r in range(0, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cell := spawn + Vector2i(dx, dy)
				var type := InteractableCatalog.type_at(world.predict_cell(cell)[1])
				if type != null and (type.id == "tree" or type.id == "bush") and not found.has(type.id):
					found[type.id] = cell
	return [scene, world, params, found]


func _cut_at(world, cell: Vector2i) -> bool:
	return world.cut_changes().get(WorldSave.chunk_key(cell), {}).has(WorldSave.cell_key(cell))


func _stump_drawn(world, cell: Vector2i, type_id: String) -> bool:
	## `cell` shows its type's stump once its chunk is drawn, and no plant.
	world.generate_chunk(world.map_to_local(cell))
	return world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, cell) == InteractableCatalog.by_id(type_id).leaves_atlas() \
			and world.get_cell_source_id(1, cell) == -1 and world.choppable(cell) == null


func _test_cut_save_round_trip() -> int:
	## A cut tree and bush are written as chunk-keyed entries naming the
	## type's save_key and the cut's age in seconds of play. Through a file
	## and a fresh apply of the params, they come back as stumps when the
	## chunk is drawn, and keep their age, so regrowth waits only the rest of
	## the delay. Entries that are not cuts, unknown types and cells the map
	## no longer grows that type on are left out.
	print("-- test_cut_save_round_trip")
	var fail := 0
	var setup := _cut_save_scene()
	var scene = setup[0]
	var world = setup[1]
	var params: MapGenParams = setup[2]
	var found: Dictionary = setup[3]
	if not found.has("tree") or not found.has("bush"):
		printerr("FAIL cut_save_round_trip: seed 7 has no tree or bush near the spawn: %s" % found)
		scene.queue_free()
		return 1
	var tree: Vector2i = found["tree"]
	var bush: Vector2i = found["bush"]
	for cell in [tree, bush]:
		world.generate_chunk(world.map_to_local(cell))
	world.play_time = 10.0
	world.cut_choppable(tree)
	world.play_time = 30.0
	world.cut_choppable(bush)
	world.play_time = 50.0
	# Save chunks are a fixed 32-cell grid, floored on negative cells.
	for pair in [[Vector2i(-20, 70), "-1,2"], [Vector2i(31, 32), "0,1"], [Vector2i(-1, -32), "-1,-1"]]:
		if WorldSave.chunk_key(pair[0]) != pair[1]:
			printerr("FAIL cut_save_round_trip: chunk_key%s = %s, want %s" % [pair[0], WorldSave.chunk_key(pair[0]), pair[1]])
			fail += 1
	var changes: Dictionary = world.cut_changes()
	var want := {
		WorldSave.chunk_key(tree): {WorldSave.cell_key(tree): {"cut": "tree", "age": 40.0}},
	}
	want.get_or_add(WorldSave.chunk_key(bush), {})[WorldSave.cell_key(bush)] = {"cut": "bush", "age": 20.0}
	if changes != want:
		printerr("FAIL cut_save_round_trip: entries %s, want %s" % [changes, want])
		fail += 1

	# Entries a load must skip: another kind of change, an unknown type, a
	# type the map does not grow on that cell, and a bad cell key.
	var bare := Vector2i.MAX
	for dx in range(1, 40):
		if bare == Vector2i.MAX and world.predict_cell(tree + Vector2i(dx, 0))[1] == world.NO_PLANT:
			bare = tree + Vector2i(dx, 0)
	var saved_world := WorldSave.new(params)
	saved_world.object_changes = changes.duplicate(true)
	var extra: Dictionary = saved_world.object_changes.get_or_add(WorldSave.chunk_key(bare), {})
	extra[WorldSave.cell_key(bare)] = {"cut": "tree", "age": 1.0}
	extra[WorldSave.cell_key(bare + Vector2i(0, 1))] = {"cut": "palm", "age": 1.0}
	extra[WorldSave.cell_key(bare + Vector2i(0, 2))] = {"removed": true}
	extra["not a cell"] = {"cut": "tree", "age": 1.0}
	var saved := MapSave.save_world(saved_world, "test_cut_save_round_trip")
	var loaded := MapSave.load_world(saved["path"])
	DirAccess.remove_absolute(saved["path"])
	if saved["error"] != "" or loaded["error"] != "":
		printerr("FAIL cut_save_round_trip: save %s load %s" % [saved["error"], loaded["error"]])
		scene.queue_free()
		return fail + 1

	scene._apply_params_to_world(params)  # a fresh world: no cuts, no tiles
	world.play_time = 1000.0
	var restored: int = world.restore_cuts(loaded["world"].object_changes)
	if restored != 2 or world.cut_changes() != want:
		printerr("FAIL cut_save_round_trip: restored %d, entries %s, want 2 and %s" % [restored, world.cut_changes(), want])
		fail += 1
	for pair in [[tree, "tree"], [bush, "bush"]]:
		if not _stump_drawn(world, pair[0], pair[1]):
			printerr("FAIL cut_save_round_trip: no %s stump at %s after the load" % [pair[1], pair[0]])
			fail += 1
	if _cut_at(world, bare):
		printerr("FAIL cut_save_round_trip: a cut on %s, where the map grows no tree, came back" % bare)
		fail += 1

	# The age carried over: the tree (cut 40 s before the save) regrows
	# after the rest of its delay, not a full delay from the load.
	var delay: float = InteractableCatalog.by_id("tree").regrow_delay
	world.play_time = 1000.0 + delay - 40.0 - 1.0
	var early: int = world.regrow_due()
	world.play_time = 1000.0 + delay - 40.0 + 1.0
	world.regrow_due()
	if early != 0 or _cut_at(world, tree):
		printerr("FAIL cut_save_round_trip: regrowth after the load: early %d, tree cut %s" % [early, _cut_at(world, tree)])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_cut_save_round_trip (tree %s, bush %s)" % [tree, bush])
	return fail


func _test_cut_save_in_game() -> int:
	## Save in the in-game menu writes this world's cuts; loading that save
	## (MapGen.load_map_inputs) and starting it the way setup_server does puts
	## the stump back before any chunk is drawn. A loaded save whose params
	## were changed before starting brings no cuts.
	print("-- test_cut_save_in_game")
	var fail := 0
	var setup := _cut_save_scene()
	var scene = setup[0]
	var world = setup[1]
	var params: MapGenParams = setup[2]
	var tree: Vector2i = setup[3].get("tree", Vector2i.MAX)
	if tree == Vector2i.MAX:
		printerr("FAIL cut_save_in_game: seed 7 has no tree near the spawn")
		scene.queue_free()
		return 1
	world.generate_chunk(world.map_to_local(tree))
	world.cut_choppable(tree)
	var menu = scene.get_node("CanvasLayer1/InGameMenu")
	var result: Dictionary = menu.save_world()
	var map_gen = root.get_node("MapGen")
	var before: MapGenParams = map_gen.params
	if result["error"] != "" or map_gen.load_map_inputs(result["path"]) != "":
		printerr("FAIL cut_save_in_game: save %s" % result["error"])
		DirAccess.remove_absolute(result["path"])
		map_gen.params = before
		scene.queue_free()
		return 1

	# What setup_server does with the params the main menu passes.
	scene.world_params = map_gen.params.duplicate_params()
	scene._apply_params_to_world(scene.world_params)
	var drawn_before: int = world.get_used_cells(0).size()
	var restored: int = scene._restore_loaded_world()
	if drawn_before != 0 or restored != 1 or not _cut_at(world, tree) or not _stump_drawn(world, tree, "tree"):
		printerr("FAIL cut_save_in_game: restored %d (cells drawn first %d), stump at %s %s"
				% [restored, drawn_before, tree, _cut_at(world, tree)])
		fail += 1
	if scene._restore_loaded_world() != 0:
		printerr("FAIL cut_save_in_game: the loaded cuts were applied twice")
		fail += 1

	# Load again, then change the params before starting: no cuts.
	map_gen.load_map_inputs(result["path"])
	var edited: MapGenParams = map_gen.params.duplicate_params()
	edited.altitude_seed += 1
	scene.world_params = edited
	scene._apply_params_to_world(edited)
	if scene._restore_loaded_world() != 0 or _cut_at(world, tree):
		printerr("FAIL cut_save_in_game: cuts came back on edited params")
		fail += 1
	DirAccess.remove_absolute(result["path"])
	map_gen.params = before
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_cut_save_in_game (tree %s)" % tree)
	return fail


func _test_cut_save_late_join() -> int:
	## A host loads a save with a cut tree and bush and a client joins. The
	## client gets the host's cut list with the map params and draws the same
	## stumps: for each cut cell, the same tiles and the same blocking as
	## the host. The host is a second process (tests/cut_sync_probe.gd).
	print("-- test_cut_save_late_join")
	var setup := _cut_save_scene()
	var probe_scene = setup[0]
	var params: MapGenParams = setup[2]
	var found: Dictionary = setup[3]
	probe_scene.queue_free()
	await process_frame
	if not found.has("tree") or not found.has("bush"):
		printerr("FAIL cut_save_late_join: seed 7 has no tree or bush near the spawn: %s" % found)
		return 1
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL cut_save_late_join found no free UDP port")
		return 1
	var world_save := WorldSave.new(params)
	for pair in [[found["tree"], "tree", 40.0], [found["bush"], "bush", 20.0]]:
		world_save.object_changes.get_or_add(WorldSave.chunk_key(pair[0]), {})[WorldSave.cell_key(pair[0])] = {"cut": pair[1], "age": pair[2]}
	var saved := MapSave.save_world(world_save, "test_cut_save_late_join_%d_%d" % [OS.get_process_id(), port])
	var save_path := ProjectSettings.globalize_path(saved["path"])
	var out := OS.get_user_data_dir().path_join("cut_sync_%d_%d.json" % [OS.get_process_id(), port])
	DirAccess.remove_absolute(out)
	DirAccess.remove_absolute(out + ".stop")
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/cut_sync_probe.gd", "--", "--host", "--port=%d" % port, "--save=" + save_path, "--out=" + out])
	if saved["error"] != "" or pid <= 0:
		printerr("FAIL cut_save_late_join: save %s, host pid %d" % [saved["error"], pid])
		DirAccess.remove_absolute(saved["path"])
		return 1
	var read := func() -> Dictionary:
		var data = JSON.parse_string(FileAccess.get_file_as_string(out)) if FileAccess.file_exists(out) else null
		return data if data is Dictionary else {}
	var fail := 0
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and OS.is_process_running(pid) and read.call().get("cells", {}).size() < 2:
		await process_frame
	var host: Dictionary = read.call()
	var scene = null
	if host.get("cells", {}).size() != 2:
		printerr("FAIL cut_save_late_join: the host did not report its 2 cuts: %s" % host)
		fail += 1
	else:
		scene = load("res://flagoria_main.tscn").instantiate()
		root.add_child(scene)
		scene.get_node("CanvasLayer2/MainMenu").hide()
		var world = scene.get_node("World/worldMap")
		scene.add_player_joined(port)
		while Time.get_ticks_msec() < deadline and (scene.world_params == null or world.cut_changes().is_empty()):
			await process_frame
		for _i in 5:
			await process_frame  # let the client draw its chunks
		var client_cuts: Dictionary = world.cut_changes()
		for chunk in host["cuts"]:
			for key in host["cuts"][chunk]:
				var want: Dictionary = host["cells"][key]
				var got: Dictionary = JSON.parse_string(JSON.stringify(load("res://tests/cut_sync_probe.gd").cell_state(world, WorldSave.parse_cell(key))))
				if not client_cuts.get(chunk, {}).has(key) or got != want or want["clear"] != true:
					printerr("FAIL cut_save_late_join: cell %s on the client %s (cut %s), on the host %s"
							% [key, got, client_cuts.get(chunk, {}).has(key), want])
					fail += 1
		if client_cuts.keys() != host["cuts"].keys():
			printerr("FAIL cut_save_late_join: client cuts %s, host cuts %s" % [client_cuts, host["cuts"]])
			fail += 1
	FileAccess.open(out + ".stop", FileAccess.WRITE).close()
	deadline = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and OS.is_process_running(pid):
		await process_frame
	if OS.is_process_running(pid):
		OS.kill(pid)
	if scene:
		scene.enet_peer.close()
		scene.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		scene.queue_free()
	for path in [saved["path"], out, out + ".stop", out + ".tmp"]:
		DirAccess.remove_absolute(path)
	await process_frame
	if fail == 0:
		print("PASS test_cut_save_late_join (%s)" % host["cuts"])
	return fail


func _test_cut_replace() -> int:
	## A joining client takes the host's cut list as the exact set
	## (world.replace_cuts, #223): a cut missing from the list grows back, a
	## listed one stays a stump, and applying the list again adds nothing.
	## A live cut (world.cut_grown) of a cell already cut, or of bare ground,
	## does nothing, so the second of two cuts of one cell earns no wood.
	print("-- test_cut_replace")
	var setup := _cut_save_scene()
	var scene = setup[0]
	var world = setup[1]
	var tree: Vector2i = setup[3]["tree"]
	var bush: Vector2i = setup[3]["bush"]
	var fail := 0
	world.generate_chunk(world.map_to_local(tree))
	world.generate_chunk(world.map_to_local(bush))
	if world.cut_grown(tree) == null or world.cut_grown(bush) == null:
		printerr("FAIL cut_replace: could not cut %s and %s" % [tree, bush])
		fail += 1
	if world.cut_grown(tree) != null or world.cut_grown(world.resolve_player_spawn()) != null:
		printerr("FAIL cut_replace: a second cut, or a cut of the spawn cell, cut something")
		fail += 1
	var changes: Dictionary = world.cut_changes().duplicate(true)
	changes[WorldSave.chunk_key(tree)].erase(WorldSave.cell_key(tree))
	if changes[WorldSave.chunk_key(tree)].is_empty():
		changes.erase(WorldSave.chunk_key(tree))
	for i in 2:
		var count: int = world.replace_cuts(changes)
		if count != 1 or _cut_at(world, tree) or not _cut_at(world, bush) or not _stump_drawn(world, bush, "bush") \
				or world.choppable(tree) == null:
			printerr("FAIL cut_replace pass %d: %d cuts, tree cut %s (choppable %s), bush stump %s"
					% [i, count, _cut_at(world, tree), world.choppable(tree), _stump_drawn(world, bush, "bush")])
			fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_cut_replace")
	return fail
