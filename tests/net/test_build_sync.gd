extends "res://tests/helpers/test_helpers.gd"
## Plank bridges during two-player play (#297).

const PROBE := "res://tests/cut_sync_probe.gd"


func _test_build_sync_two_players() -> int:
	## A host and a client (each its own process, tests/cut_sync_probe.gd) on
	## seed 7 both place a one-cell plank on shore water. The host decides
	## each place; then every plank cell is a bridge and walkable on both
	## peers, both hold the same bridge list, and each spent only its own
	## wood. A second client joining after those places sees the same set.
	## Time cost: about 8–15 s alone with --only=build_sync_two_players
	## (three Godot peers); Netcode stress runs it 20×.
	print("-- test_build_sync_two_players")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("CanvasLayer2/MainMenu").hide()
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	var params := _spawn_params(7, 0.0)
	params.ensure_seeds()
	scene._apply_params_to_world(params)
	var spawn: Vector2i = world.resolve_player_spawn()
	var land := func(c: Vector2i) -> bool:
		return not world.has_bridge(c) and world.ground_is_walkable(world.predict_cell(c)[0])
	var shores: Array[Vector2i] = []
	for r in range(0, 50):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cell := spawn + Vector2i(dx, dy)
				if world.predict_cell(cell)[0] != TileCatalog.WATER:
					continue
				var touches := false
				for n in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					if land.call(cell + n):
						touches = true
						break
				if touches:
					shores.append(cell)
				if shores.size() >= 2:
					break
			if shores.size() >= 2:
				break
		if shores.size() >= 2:
			break
	scene.queue_free()
	await process_frame
	if shores.size() < 2:
		printerr("FAIL build_sync_two_players: seed 7 has too few shore water cells near spawn: %s" % [shores])
		return 1
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL build_sync_two_players found no free UDP port")
		return 1
	var dir := OS.get_user_data_dir().path_join("build_sync_%d_%d" % [OS.get_process_id(), port])
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var saved := MapSave.save_world(WorldSave.new(params), "test_build_sync_%d_%d" % [OS.get_process_id(), port])
	var places_of := [[shores[0]], [shores[1]]]  # host, client
	var all: Array = places_of[0] + places_of[1]
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
	var bridge_set := func(i: int) -> Array:
		var keys := []
		for entry in read.call(i).get("bridges", []):
			keys.append(str(entry))
		keys.sort()
		return keys
	var want_keys := all.map(func(c: Vector2i) -> String: return WorldSave.cell_key(c))
	want_keys.sort()
	var same := func(i: int) -> bool:
		if bridge_set.call(i) != want_keys or bridge_set.call(0) != want_keys:
			return false
		for key in want_keys:
			var here = read.call(i).get("cells", {}).get(key)
			if here == null or here != read.call(0).get("cells", {}).get(key) or here.get("bridge") != true:
				return false
		return true

	var fail := 0
	launch.call(["--host", "--save=" + ProjectSettings.globalize_path(saved["path"])])
	if saved["error"] != "" or not await wait_for.call(func() -> bool: return read.call(0).get("ready", false), 30000):
		printerr("FAIL build_sync_two_players: the host did not start: save %s, %s" % [saved["error"], read.call(0)])
		fail += 1
	else:
		launch.call([])
		if not await wait_for.call(func() -> bool: return read.call(1).get("ready", false), 30000):
			printerr("FAIL build_sync_two_players: the client did not join: %s" % read.call(1))
			fail += 1
		else:
			for i in 2:
				var f := FileAccess.open(outs[i] + ".plank", FileAccess.WRITE)
				f.store_string(";".join(places_of[i].map(func(c: Vector2i) -> String: return WorldSave.cell_key(c))))
				f.close()
			# Each places one plank (1 wood). Start wood is 0; probe adds enough.
			if not await wait_for.call(func() -> bool: return same.call(1) \
					and read.call(0).get("wood", -1) == 0 and read.call(1).get("wood", -1) == 0, 20000):
				printerr("FAIL build_sync_two_players: after both place %s, host %s, client %s"
						% [places_of, read.call(0), read.call(1)])
				fail += 1
			launch.call([])
			if not await wait_for.call(func() -> bool: return read.call(2).get("ready", false) and same.call(2), 30000):
				printerr("FAIL build_sync_two_players: the late joiner %s, host %s" % [read.call(2), read.call(0)])
				fail += 1
			for i in outs.size():
				if not read.call(i).get("errors", []).is_empty():
					printerr("FAIL build_sync_two_players: peer %d logged errors: %s" % [i, read.call(i)["errors"]])
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
		print("PASS test_build_sync_two_players (host place %s, client place %s)" % places_of)
	return fail
