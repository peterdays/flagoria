extends "res://tests/helpers/test_helpers.gd"
## Regrowth of cut trees and bushes during two-player play (#298).

const PROBE := "res://tests/cut_sync_probe.gd"
const HOST_REGROW := 6.0  ## seconds; the host's delay is the one that counts
const CLIENT_REGROW := 1.0  ## a client's own, shorter delay, which it must not use
const SAME_TIME_MS := 500  ## how far apart two peers may show one regrowth


func _test_regrow_sync_two_players() -> int:
	## A host and a client (each its own process, tests/cut_sync_probe.gd)
	## on seed 7 each cut a plant near the spawn: the host a tree, the client
	## a bush. The client's own regrow delay is shorter than the host's, and
	## it also sends the host a forged apply_regrow: the stumps stay on both
	## until the host's delay is up. A second client joining before that gets
	## the stumps with the host's ages. Then the host regrows both, and every
	## peer shows the same plant back within SAME_TIME_MS of the host. A third
	## client joining after that sees no cuts and the same plants.
	print("-- test_regrow_sync_two_players")
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
				var cell := spawn + Vector2i(dx, dy)
				var type := InteractableCatalog.type_at(world.predict_cell(cell)[1])
				if maxi(absi(dx), absi(dy)) == r and type != null and found.has(type.id) and found[type.id].is_empty():
					found[type.id].append(cell)
	scene.queue_free()
	await process_frame
	if found["tree"].is_empty() or found["bush"].is_empty():
		printerr("FAIL regrow_sync_two_players: seed 7 has no tree or bush near the spawn: %s" % found)
		return 1
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL regrow_sync_two_players found no free UDP port")
		return 1
	var dir := OS.get_user_data_dir().path_join("regrow_sync_%d_%d" % [OS.get_process_id(), port])
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var saved := MapSave.save_world(WorldSave.new(params), "test_regrow_sync_%d_%d" % [OS.get_process_id(), port])
	var cells: Array = [found["tree"][0], found["bush"][0]]  # cut by the host, by the client
	var keys: Array = cells.map(func(c: Vector2i) -> String: return WorldSave.cell_key(c))
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
	var ages := func(i: int) -> Dictionary:
		## Cell key -> age in seconds, for each cut peer i holds.
		var out := {}
		var cuts: Dictionary = read.call(i).get("cuts", {})
		for chunk in cuts:
			for key in cuts[chunk]:
				out[key] = float(cuts[chunk][key]["age"])
		return out
	var holds_both := func(i: int) -> bool:
		var a: Dictionary = ages.call(i)
		return a.size() == 2 and a.has(keys[0]) and a.has(keys[1])
	var regrown_like_host := func(i: int) -> bool:
		## Peer i holds no cut, and each cell shows what the host shows.
		var data: Dictionary = read.call(i)
		if not ages.call(i).is_empty() or not ages.call(0).is_empty():
			return false
		for key in keys:
			var here = data.get("cells", {}).get(key)
			if here == null or here != read.call(0).get("cells", {}).get(key) or here["plant"] == [-1, -1]:
				return false
		return true
	var client := ["--regrow=%s" % CLIENT_REGROW]

	var fail := 0
	launch.call(["--host", "--regrow=%s" % HOST_REGROW, "--save=" + ProjectSettings.globalize_path(saved["path"])])
	if saved["error"] != "" or not await wait_for.call(func() -> bool: return read.call(0).get("ready", false), 30000):
		printerr("FAIL regrow_sync_two_players: the host did not start: save %s, %s" % [saved["error"], read.call(0)])
		fail += 1
	else:
		launch.call(client)
		if not await wait_for.call(func() -> bool: return read.call(1).get("ready", false), 30000):
			printerr("FAIL regrow_sync_two_players: the client did not join: %s" % read.call(1))
			fail += 1
		else:
			for i in 2:  # both cut at once
				var f := FileAccess.open(outs[i] + ".cut", FileAccess.WRITE)
				f.store_string(keys[i])
				f.close()
			if not await wait_for.call(func() -> bool: return holds_both.call(0) and holds_both.call(1), 20000):
				printerr("FAIL regrow_sync_two_players: after the cuts, host %s, client %s" % [read.call(0), read.call(1)])
				fail += 1
			else:
				# Past the client's own delay, with a forged regrowth sent:
				# the stumps stay everywhere until the host's delay.
				FileAccess.open(outs[1] + ".forge", FileAccess.WRITE).close()
				await wait_for.call(func() -> bool: return ages.call(1).values().min() > CLIENT_REGROW + 1.0, 5000)
				if not holds_both.call(0) or not holds_both.call(1) or not read.call(1).get("regrown", {}).is_empty():
					printerr("FAIL regrow_sync_two_players: a stump regrew before the host's delay: host %s, client %s"
							% [read.call(0), read.call(1)])
					fail += 1
				launch.call(client)
				if not await wait_for.call(func() -> bool: return read.call(2).get("ready", false) and holds_both.call(2), 30000):
					printerr("FAIL regrow_sync_two_players: the first late joiner %s, host %s" % [read.call(2), read.call(0)])
					fail += 1
				else:
					var host_ages: Dictionary = ages.call(0)
					var joiner_ages: Dictionary = ages.call(2)
					for key in keys:
						if absf(host_ages[key] - joiner_ages[key]) > 0.5:
							printerr("FAIL regrow_sync_two_players: late joiner ages %s, host %s" % [joiner_ages, host_ages])
							fail += 1
							break
				if not await wait_for.call(func() -> bool: return regrown_like_host.call(1) and regrown_like_host.call(2),
						int(HOST_REGROW * 1000) + 10000):
					printerr("FAIL regrow_sync_two_players: after the host's delay, host %s, client %s, late joiner %s"
							% [read.call(0), read.call(1), read.call(2)])
					fail += 1
				else:
					await wait_for.call(func() -> bool: return false, 300)  # every peer wrote its last regrowth
					var spread := {}
					for key in keys:
						var times: Array = range(3).map(func(i: int) -> int: return int(read.call(i)["regrown"].get(key, 0)))
						spread[key] = times.max() - times.min()
						if times.min() == 0 or spread[key] > SAME_TIME_MS:
							printerr("FAIL regrow_sync_two_players: %s regrew at %s (host, client, late joiner)" % [key, times])
							fail += 1
					print("   regrowth spread across peers (ms): %s" % spread)
				launch.call(client)
				if not await wait_for.call(func() -> bool: return read.call(3).get("ready", false) and regrown_like_host.call(3), 30000):
					printerr("FAIL regrow_sync_two_players: the joiner after regrowth %s, host %s" % [read.call(3), read.call(0)])
					fail += 1
			if not str(read.call(0).get("errors", [])).contains("apply_regrow"):
				printerr("FAIL regrow_sync_two_players: the host did not refuse the forged apply_regrow: %s" % read.call(0))
				fail += 1
			for i in outs.size():
				# The host refuses the client's forged apply_regrow with an
				# engine error; any other error fails.
				for line in read.call(i).get("errors", []):
					if i != 0 or not "apply_regrow" in str(line):
						printerr("FAIL regrow_sync_two_players: peer %d logged errors: %s" % [i, read.call(i)["errors"]])
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
		print("PASS test_regrow_sync_two_players (host cut %s, client cut %s)" % cells)
	return fail
