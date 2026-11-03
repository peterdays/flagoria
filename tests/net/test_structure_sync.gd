extends "res://tests/helpers/test_helpers.gd"
## Placed structures reach a peer that joins (#278, join slice).

const PROBE := "res://tests/cut_sync_probe.gd"


func _test_structure_sync_join() -> int:
	## A host (its own process, tests/cut_sync_probe.gd) on seed 7 places
	## a guard post near the spawn while alone. A client that joins then
	## holds the same placement, and every footprint cell predicts, draws
	## and collides as on the host (a wall blocks on both). The client
	## cannot place itself ("multiplayer on"). It then sends a second
	## client a forged receive_map_params with a placement of its own: the
	## second client refuses it (an engine error naming receive_map_params)
	## and keeps the host's list.
	print("-- test_structure_sync_join")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("CanvasLayer2/MainMenu").hide()
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	var params := _spawn_params(7, 0.0)
	params.ensure_seeds()
	scene._apply_params_to_world(params)
	var spawn: Vector2i = world.resolve_player_spawn()
	var guard: Structure = Structure.parse(FileAccess.get_file_as_string("res://structures/guard_post.txt"))["structure"]
	var anchor = null
	for r in range(6, 40):  # clear of the players spawning at the spawn
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cell := spawn + Vector2i(dx, dy)
				if anchor == null and maxi(absi(dx), absi(dy)) == r and world.can_place_structure(guard, cell).is_empty():
					anchor = cell
	scene.queue_free()
	await process_frame
	if anchor == null:
		printerr("FAIL structure_sync_join: seed 7 has no spot for a guard post near the spawn")
		return 1
	var foot: Array = StructurePlacer.footprint(guard, anchor).keys()
	var keys: Array = foot.map(func(c: Vector2i) -> String: return WorldSave.cell_key(c))
	var want := [["guard_post", 1.0, float(anchor.x), float(anchor.y)]]  # as JSON reads it back
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL structure_sync_join found no free UDP port")
		return 1
	var dir := OS.get_user_data_dir().path_join("structure_sync_%d_%d" % [OS.get_process_id(), port])
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var saved := MapSave.save_world(WorldSave.new(params), "test_structure_sync_%d_%d" % [OS.get_process_id(), port])
	var outs: Array[String] = []
	var pids: Array[int] = []
	var launch := func(extra: Array) -> void:
		outs.append(dir.path_join("p%d.json" % outs.size()))
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", PROBE,
				"--", "--port=%d" % port, "--out=" + outs[-1], "--cells=" + ";".join(keys)]
		args.append_array(extra)
		pids.append(OS.create_process(OS.get_executable_path(), args))
	var read := func(i: int) -> Dictionary:
		var text := FileAccess.get_file_as_string(outs[i]) if FileAccess.file_exists(outs[i]) else ""
		var data = JSON.parse_string(text) if text != "" else null
		return data if data is Dictionary else {}
	var wait_for := func(cond: Callable, ms: int) -> bool:
		var until := Time.get_ticks_msec() + ms
		while Time.get_ticks_msec() < until and not cond.call():
			await process_frame
		return cond.call()
	var like_host := func(i: int) -> bool:
		## Peer i holds the host's placement, and each footprint cell is
		## predicted, drawn and blocks as on the host, with a wall somewhere.
		var data: Dictionary = read.call(i)
		if not data.get("ready", false) or data.get("placements") != want \
				or read.call(0).get("placements") != want:
			return false
		var blocked := false
		for key in keys:
			var here = data.get("cells", {}).get(key)
			if here == null or here != read.call(0).get("cells", {}).get(key):
				return false
			blocked = blocked or not here["clear"]
		return blocked

	var fail := 0
	launch.call(["--host", "--place=guard_post@%s" % WorldSave.cell_key(anchor),
			"--save=" + ProjectSettings.globalize_path(saved["path"])])
	if saved["error"] != "" or not await wait_for.call(func() -> bool: return read.call(0).get("ready", false), 30000):
		printerr("FAIL structure_sync_join: the host did not start: save %s, %s" % [saved["error"], read.call(0)])
		fail += 1
	else:
		launch.call([])
		if not await wait_for.call(func() -> bool: return like_host.call(1), 30000):
			printerr("FAIL structure_sync_join: the joiner %s, host %s" % [read.call(1), read.call(0)])
			fail += 1
		elif not "multiplayer on" in read.call(1).get("place_refused", []):
			printerr("FAIL structure_sync_join: a client could place: %s" % read.call(1).get("place_refused"))
			fail += 1
		else:
			launch.call([])
			if not await wait_for.call(func() -> bool: return like_host.call(2), 30000):
				printerr("FAIL structure_sync_join: the second joiner %s, host %s" % [read.call(2), read.call(0)])
				fail += 1
			else:
				FileAccess.open(outs[1] + ".forge_place", FileAccess.WRITE).close()
				await wait_for.call(func() -> bool: return str(read.call(2).get("errors", [])).contains("receive_map_params"), 5000)
				if not str(read.call(2).get("errors", [])).contains("receive_map_params") or not like_host.call(2):
					printerr("FAIL structure_sync_join: after a forged placement from a client, second joiner %s" % read.call(2))
					fail += 1
		for i in outs.size():
			# The second joiner refuses the forged receive_map_params with an
			# engine error; any other error fails.
			for line in read.call(i).get("errors", []):
				if i != 2 or not "receive_map_params" in str(line):
					printerr("FAIL structure_sync_join: peer %d logged errors: %s" % [i, read.call(i)["errors"]])
					fail += 1
					break

	for out in outs:
		FileAccess.open(out + ".stop", FileAccess.WRITE).close()
	await wait_for.call(func() -> bool:
		for pid in pids:
			if OS.is_process_running(pid):
				return false
		return true, 10000)
	for pid in pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	_remove_dir(dir)
	DirAccess.remove_absolute(saved["path"])
	if fail == 0:
		print("PASS test_structure_sync_join (guard post at %s, %d footprint cells)" % [anchor, keys.size()])
	return fail
