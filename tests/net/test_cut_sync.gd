extends "res://tests/helpers/test_helpers.gd"
## Tree and bush cuts during two-player play (#223).

const PROBE := "res://tests/cut_sync_probe.gd"


func _test_cut_sync_two_players() -> int:
	## A host and a client (each its own process, tests/cut_sync_probe.gd)
	## on seed 7 both cut a tree and a bush at the same time. The host
	## decides each cut; then every cut cell shows the same stump and is
	## open ground on both peers, both hold the same cut list, and each got
	## its own wood (3 per tree, 1 per bush). A second client joining after
	## those cuts sees the same set.
	print("-- test_cut_sync_two_players")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("CanvasLayer2/MainMenu").hide()
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	var params := _spawn_params(7, 0.0)
	params.ensure_seeds()
	scene._apply_params_to_world(params)
	var spawn: Vector2i = world.resolve_player_spawn()
	var found := {"tree": [], "bush": []}
	for r in range(0, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cell := spawn + Vector2i(dx, dy)
				var type := InteractableCatalog.type_at(world.predict_cell(cell)[1])
				if type != null and found.has(type.id) and found[type.id].size() < 2:
					found[type.id].append(cell)
	scene.queue_free()
	await process_frame
	if found["tree"].size() < 2 or found["bush"].size() < 2:
		printerr("FAIL cut_sync_two_players: seed 7 has too few trees and bushes near the spawn: %s" % found)
		return 1
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL cut_sync_two_players found no free UDP port")
		return 1
	var dir := OS.get_user_data_dir().path_join("cut_sync_%d_%d" % [OS.get_process_id(), port])
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var saved := MapSave.save_world(WorldSave.new(params), "test_cut_sync_%d_%d" % [OS.get_process_id(), port])
	var cuts_of := [[found["tree"][0], found["bush"][0]], [found["tree"][1], found["bush"][1]]]  # host, client
	var all: Array = cuts_of[0] + cuts_of[1]
	var cells_arg := ";".join(all.map(func(c: Vector2i) -> String: return WorldSave.cell_key(c)))
	var outs: Array[String] = []
	var pids: Array[int] = []
	var launch := func(extra: Array) -> void:
		outs.append(dir.path_join("p%d.json" % outs.size()))
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", PROBE,
				"--", "--port=%d" % port, "--out=" + outs[-1], "--cells=" + cells_arg]
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
	var cut_set := func(i: int) -> Array:
		var keys := []
		var cuts: Dictionary = read.call(i).get("cuts", {})
		for chunk in cuts:
			for key in cuts[chunk]:
				keys.append(key)
		keys.sort()
		return keys
	var want_keys := all.map(func(c: Vector2i) -> String: return WorldSave.cell_key(c))
	want_keys.sort()
	var same := func(i: int) -> bool:
		## Peer i has every cut, and each cell shows what the host shows: a
		## stump and open ground.
		if cut_set.call(i) != want_keys or cut_set.call(0) != want_keys:
			return false
		for key in want_keys:
			var here = read.call(i).get("cells", {}).get(key)
			if here == null or here != read.call(0).get("cells", {}).get(key) or here["clear"] != true:
				return false
		return true

	var fail := 0
	launch.call(["--host", "--save=" + ProjectSettings.globalize_path(saved["path"])])
	if saved["error"] != "" or not await wait_for.call(func() -> bool: return read.call(0).get("ready", false), 30000):
		printerr("FAIL cut_sync_two_players: the host did not start: save %s, %s" % [saved["error"], read.call(0)])
		fail += 1
	else:
		launch.call([])
		if not await wait_for.call(func() -> bool: return read.call(1).get("ready", false), 30000):
			printerr("FAIL cut_sync_two_players: the client did not join: %s" % read.call(1))
			fail += 1
		else:
			for i in 2:  # both cut at once
				var f := FileAccess.open(outs[i] + ".cut", FileAccess.WRITE)
				f.store_string(";".join(cuts_of[i].map(func(c: Vector2i) -> String: return WorldSave.cell_key(c))))
				f.close()
			var wood := InteractableCatalog.by_id("tree").amount_of(Inventory.WOOD) \
					+ InteractableCatalog.by_id("bush").amount_of(Inventory.WOOD)
			if not await wait_for.call(func() -> bool: return same.call(1) and read.call(0).get("wood", 0) == wood \
					and read.call(1).get("wood", 0) == wood, 20000):
				printerr("FAIL cut_sync_two_players: after both cut %s, host %s, client %s" % [cuts_of, read.call(0), read.call(1)])
				fail += 1
			launch.call([])
			if not await wait_for.call(func() -> bool: return read.call(2).get("ready", false) and same.call(2), 30000):
				printerr("FAIL cut_sync_two_players: the late joiner %s, host %s" % [read.call(2), read.call(0)])
				fail += 1
			for i in outs.size():
				if not read.call(i).get("errors", []).is_empty():
					printerr("FAIL cut_sync_two_players: peer %d logged errors: %s" % [i, read.call(i)["errors"]])
					fail += 1

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
		print("PASS test_cut_sync_two_players (host cut %s, client cut %s)" % cuts_of)
	return fail


func _test_dead_cut_client() -> int:
	## A host and a client (tests/cut_sync_probe.gd) on seed 7 (#349). The
	## host kills the client's player; the dead client drags a selection over
	## a tree in reach, then sends the host request_cut for it directly. The
	## host refuses both: 1 s later neither peer holds a cut and the client's
	## wood is unchanged.
	print("-- test_dead_cut_client")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("CanvasLayer2/MainMenu").hide()
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	var params := _spawn_params(7, 0.0)
	params.ensure_seeds()
	scene._apply_params_to_world(params)
	var spawn: Vector2i = world.resolve_player_spawn()
	var tree := Vector2i.MAX
	for r in range(2, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cell := spawn + Vector2i(dx, dy)
				var type := InteractableCatalog.type_at(world.predict_cell(cell)[1])
				if tree == Vector2i.MAX and maxi(absi(dx), absi(dy)) == r and type != null and type.id == "tree":
					tree = cell
	scene.queue_free()
	await process_frame
	var port := _free_udp_port()
	if tree == Vector2i.MAX or port == 0:
		printerr("FAIL dead_cut_client: tree %s near the spawn, port %d" % [tree, port])
		return 1
	var saved := MapSave.save_world(WorldSave.new(params), "test_dead_cut_%d_%d" % [OS.get_process_id(), port])
	var dir := OS.get_user_data_dir().path_join("dead_cut_%d_%d" % [OS.get_process_id(), port])
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var outs: Array[String] = []
	var pids: Array[int] = []
	var launch := func(extra: Array) -> void:
		outs.append(dir.path_join("p%d.json" % outs.size()))
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", PROBE,
				"--", "--port=%d" % port, "--out=" + outs[-1], "--cells=" + WorldSave.cell_key(tree)]
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
	var write := func(path: String, text: String) -> void:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(text)
		f.close()

	var fail := 0
	launch.call(["--host", "--save=" + ProjectSettings.globalize_path(saved["path"])])
	launch.call([])
	if saved["error"] != "" or not await wait_for.call(func() -> bool:
			return read.call(0).get("ready", false) and read.call(1).get("ready", false), 30000):
		printerr("FAIL dead_cut_client: the session did not start: save %s, host %s, client %s"
				% [saved["error"], read.call(0), read.call(1)])
		fail += 1
	else:
		write.call(outs[1] + ".dead_cut", WorldSave.cell_key(tree))
		write.call(outs[0] + ".kill", read.call(1)["id"])
		if not await wait_for.call(func() -> bool: return read.call(1).get("dead_cut", -1) >= 0, 10000):
			printerr("FAIL dead_cut_client: the client never cut while dead: %s" % read.call(1))
			fail += 1
		else:
			var until := Time.get_ticks_msec() + 1000  # the host's answer would be back by now
			while Time.get_ticks_msec() < until:
				await process_frame
			var host: Dictionary = read.call(0)
			var client: Dictionary = read.call(1)
			if client.get("dead_cut", 0) < 1 or not client.get("dead", false) or not host.get("cuts", {}).is_empty() \
					or not client.get("cuts", {}).is_empty() or client.get("wood", -1) != 0:
				printerr("FAIL dead_cut_client: tree %s, host %s, client %s" % [tree, host, client])
				fail += 1
		for i in outs.size():
			if not read.call(i).get("errors", []).is_empty():
				printerr("FAIL dead_cut_client: peer %d logged errors: %s" % [i, read.call(i)["errors"]])
				fail += 1

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
		print("PASS test_dead_cut_client (tree %s)" % tree)
	return fail
