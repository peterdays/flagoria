extends "res://tests/helpers/test_helpers.gd"
## Placed structures, the starting castle among them, reach a peer that joins (#278, join slice).

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
	var peers := _start_peers("structure_sync", params, keys)
	if peers.is_empty():
		printerr("FAIL structure_sync_join found no free UDP port")
		return 1
	var saved: Dictionary = peers["saved"]
	var launch := func(extra: Array) -> void: _launch(peers, extra)
	var read := func(i: int) -> Dictionary: return _read(peers, i)
	var wait_for := _wait_for
	var like_host := func(i: int) -> bool:
		## Peer i holds the host's placement, and each footprint cell is
		## predicted, drawn and blocks as on the host, with a wall somewhere.
		## The host's list also holds its starting castle (#271).
		var data: Dictionary = read.call(i)
		var host_list = read.call(0).get("placements")
		if not data.get("ready", false) or data.get("placements") != host_list \
				or not (host_list is Array and want[0] in host_list):
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
				FileAccess.open(peers["outs"][1] + ".forge_place", FileAccess.WRITE).close()
				await wait_for.call(func() -> bool: return str(read.call(2).get("errors", [])).contains("receive_map_params"), 5000)
				if not str(read.call(2).get("errors", [])).contains("receive_map_params") or not like_host.call(2):
					printerr("FAIL structure_sync_join: after a forged placement from a client, second joiner %s" % read.call(2))
					fail += 1
		for i in peers["outs"].size():
			# The second joiner refuses the forged receive_map_params with an
			# engine error; any other error fails.
			for line in read.call(i).get("errors", []):
				if i != 2 or not "receive_map_params" in str(line):
					printerr("FAIL structure_sync_join: peer %d logged errors: %s" % [i, read.call(i)["errors"]])
					fail += 1
					break

	await _stop_peers(peers)
	if fail == 0:
		print("PASS test_structure_sync_join (guard post at %s, %d footprint cells)" % [anchor, keys.size()])
	return fail


func _test_castle_sync_join() -> int:
	## A host (tests/cut_sync_probe.gd) on seed 7 starts through setup_server,
	## which places its starting castle while alone (#271). A client that
	## joins then holds the same host castle plus a castle the host placed for
	## the joiner, and every host-castle footprint cell predicts,
	## draws and collides as on the host, so no wall is solid on one peer
	## only. The joiner spawns on the land outside the gate (the spot
	## free_spawn_position picks there, the host's player standing on the
	## gate front), clear and outside the walls on both peers, and the host
	## sees it there too.
	print("-- test_castle_sync_join")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("CanvasLayer2/MainMenu").hide()
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	var params := _spawn_params(7, 0.0)
	params.ensure_seeds()
	scene._apply_params_to_world(params)
	var placed: bool = world.place_start_castle(1)
	var castle := StartCastle.structure()
	var anchor: Vector2i = world.placed_structures().values()[0]["anchor"] if placed else Vector2i.ZERO
	var front: Vector2i = world.resolve_player_spawn()
	var host_at: Array[Vector2] = [world.map_to_local(front)]  # the host's player stands on the gate front
	var spot: Vector2 = world.free_spawn_position(front, host_at)
	var spot_cell: Vector2i = world.local_to_map(spot)
	scene.queue_free()
	await process_frame
	if not placed:
		printerr("FAIL castle_sync_join: seed 7 has no spot for the starting castle")
		return 1
	var foot: Array = StructurePlacer.footprint(castle, anchor).keys()
	var keys: Array = foot.map(func(c: Vector2i) -> String: return WorldSave.cell_key(c))
	keys.append_array([WorldSave.cell_key(front), WorldSave.cell_key(spot_cell)])
	var want := [["castle", 1.0, float(anchor.x), float(anchor.y)]]  # as JSON reads it back
	var peers := _start_peers("castle_sync", params, keys)
	if peers.is_empty():
		printerr("FAIL castle_sync_join found no free UDP port")
		return 1
	var saved: Dictionary = peers["saved"]
	var fail := 0
	_launch(peers, ["--host", "--save=" + ProjectSettings.globalize_path(saved["path"])])
	if saved["error"] != "" or not await _wait_for(func() -> bool: return _read(peers, 0).get("ready", false), 30000):
		printerr("FAIL castle_sync_join: the host did not start: save %s, %s" % [saved["error"], _read(peers, 0)])
		fail += 1
	else:
		_launch(peers, [])
		var joined := func() -> bool:
			var data := _read(peers, 1)
			var id := str(data.get("id"))
			return data.get("ready", false) and data.get("players", {}).has(id) and _read(peers, 0).get("players", {}).has(id)
		await _wait_for(joined, 30000)
		var host := _read(peers, 0)
		var peer := _read(peers, 1)
		var me := str(peer.get("id"))
		var joiner_id := int(str(peer.get("id")))
		var castles := _castle_rows(host.get("placements"))
		var peer_castles := _castle_rows(peer.get("placements"))
		if host.get("placements") != peer.get("placements") or castles != peer_castles \
				or castles.size() != 2 or not _has_castle(castles, 1, anchor) \
				or not _has_owner(castles, joiner_id):
			printerr("FAIL castle_sync_join: placements host %s, joiner %s, want host castle %s and joiner %s"
					% [host.get("placements"), peer.get("placements"), anchor, joiner_id])
			fail += 1
		var walls := 0
		var differ: Array = []
		for key in keys:
			var here = peer.get("cells", {}).get(key)
			if here == null or here != host.get("cells", {}).get(key):
				differ.append(key)
			elif not here["clear"]:
				walls += 1
		if not differ.is_empty():
			printerr("FAIL castle_sync_join: %d of %d cells differ, first %s joiner %s, host %s" % [differ.size(), keys.size(),
					differ[0], peer.get("cells", {}).get(differ[0]), host.get("cells", {}).get(differ[0])])
			fail += 1
		elif walls == 0:
			printerr("FAIL castle_sync_join: no castle cell blocks on the peers")
			fail += 1
		var cell_on := func(data: Dictionary, which: String) -> Variant:
			var at = data.get("players", {}).get(which)
			return Vector2i(at[0], at[1]) if at is Array else null
		var at_joiner: Variant = cell_on.call(peer, me)
		var at_host: Variant = cell_on.call(host, me)
		var clear_both: bool = keys.has(WorldSave.cell_key(spot_cell)) \
				and peer.get("cells", {}).get(WorldSave.cell_key(spot_cell), {}).get("clear", false) \
				and host.get("cells", {}).get(WorldSave.cell_key(spot_cell), {}).get("clear", false)
		if at_joiner != spot_cell or at_host != spot_cell or spot_cell in foot or not clear_both:
			printerr("FAIL castle_sync_join: joiner at %s (host sees %s), want %s outside the gate front %s, clear on both"
					% [at_joiner, at_host, spot_cell, front])
			fail += 1
		elif cell_on.call(host, "1") != front:
			printerr("FAIL castle_sync_join: host player at %s, want the gate front %s" % [cell_on.call(host, "1"), front])
			fail += 1
		for i in peers["outs"].size():
			if not _read(peers, i).get("errors", []).is_empty():
				printerr("FAIL castle_sync_join: peer %d logged errors: %s" % [i, _read(peers, i)["errors"]])
				fail += 1
	await _stop_peers(peers)
	if fail == 0:
		print("PASS test_castle_sync_join (castle at %s, %d footprint cells, joiner at %s)" % [anchor, foot.size(), spot_cell])
	return fail


func _castle_rows(list) -> Array:
	var out: Array = []
	if not list is Array:
		return out
	for entry in list:
		if entry is Array and entry.size() >= 4 and str(entry[0]) == "castle":
			out.append([int(entry[1]), int(entry[2]), int(entry[3])])
	return out


func _has_castle(rows: Array, owner: int, anchor: Vector2i) -> bool:
	return [owner, anchor.x, anchor.y] in rows


func _has_owner(rows: Array, owner: int) -> bool:
	for row in rows:
		if int(row[0]) == owner:
			return true
	return false


func _start_peers(label: String, params: MapGenParams, keys: Array) -> Dictionary:
	## A session dir and a saved world for tests/cut_sync_probe.gd peers on
	## a free port, reporting `keys`; {} when no port is free.
	var port := _free_udp_port()
	if port == 0:
		return {}
	var dir := OS.get_user_data_dir().path_join("%s_%d_%d" % [label, OS.get_process_id(), port])
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var saved := MapSave.save_world(WorldSave.new(params), "test_%s_%d_%d" % [label, OS.get_process_id(), port])
	var outs: Array[String] = []
	var pids: Array[int] = []
	return {"port": port, "dir": dir, "saved": saved, "keys": keys, "outs": outs, "pids": pids}


func _launch(peers: Dictionary, extra: Array) -> void:
	## Start one more probe peer; its JSON goes to peers["outs"][-1].
	peers["outs"].append(peers["dir"].path_join("p%d.json" % peers["outs"].size()))
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", PROBE,
			"--", "--port=%d" % peers["port"], "--out=" + peers["outs"][-1], "--cells=" + ";".join(peers["keys"])]
	args.append_array(extra)
	peers["pids"].append(OS.create_process(OS.get_executable_path(), args))


func _read(peers: Dictionary, i: int) -> Dictionary:
	var out: String = peers["outs"][i]
	var text := FileAccess.get_file_as_string(out) if FileAccess.file_exists(out) else ""
	var data = JSON.parse_string(text) if text != "" else null
	return data if data is Dictionary else {}


func _wait_for(cond: Callable, ms: int) -> bool:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until and not cond.call():
		await process_frame
	return cond.call()


func _stop_peers(peers: Dictionary) -> void:
	## Ask every probe to stop, kill any still running after 10 s, and
	## remove the session dir and the saved world.
	for out in peers["outs"]:
		FileAccess.open(out + ".stop", FileAccess.WRITE).close()
	await _wait_for(func() -> bool:
		for pid in peers["pids"]:
			if OS.is_process_running(pid):
				return false
		return true, 10000)
	for pid in peers["pids"]:
		if OS.is_process_running(pid):
			OS.kill(pid)
	_remove_dir(peers["dir"])
	DirAccess.remove_absolute(peers["saved"]["path"])
