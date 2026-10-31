extends "res://tests/helpers/test_helpers.gd"
## Two-player host and join smoke test.


func _test_two_player_smoke() -> int:
	## The multiplayer gate (#45): a dedicated server and two clients, each its
	## own headless process (tests/late_join_probe.gd). Every peer sees both
	## players; then client A walks by holding an input action and both the
	## server and client B see A move to where A has it.
	print("-- test_two_player_smoke")
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL two_player_smoke found no free UDP port")
		return 1
	var dir := OS.get_user_data_dir().path_join("smoke_%d_%d" % [OS.get_process_id(), port])
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var outs: Array[String] = []
	var pids: Array[int] = []
	for extra in [["--dedicated"], [], []]:
		outs.append(dir.path_join("p%d.json" % outs.size()))
		# Each probe quits by itself after 90 s, whatever happens to this run.
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"),
				"--script", "res://tests/late_join_probe.gd", "--", "--port=%d" % port, "--out=" + outs[-1]]
		args.append_array(extra)
		pids.append(OS.create_process(OS.get_executable_path(), args))
		if outs.size() == 1:
			# Clients join once the server is up, so their spots are picked.
			var up := Time.get_ticks_msec() + 30000
			while Time.get_ticks_msec() < up and not FileAccess.file_exists(outs[0]):
				await process_frame
	var read := func(i: int) -> Dictionary:
		var text := FileAccess.get_file_as_string(outs[i])
		var data = JSON.parse_string(text) if text != "" else null
		return data if data is Dictionary else {}
	var seen := func(viewer: int, id: String) -> Vector2:
		## Where peer `viewer` sees player `id`, or Vector2.INF.
		var p = read.call(viewer).get("players", {}).get(id)
		return Vector2(p["pos"][0], p["pos"][1]) if p != null else Vector2.INF
	var wait_for := func(cond: Callable, ms: int) -> bool:
		var until := Time.get_ticks_msec() + ms
		while Time.get_ticks_msec() < until and not cond.call():
			await process_frame
		return cond.call()

	var fail := 0
	var both_seen := func() -> bool:
		var ids := [read.call(1).get("id", ""), read.call(2).get("id", "")]
		for viewer in 3:
			for id in ids:
				if id in ["", "0", "1"] or seen.call(viewer, id) == Vector2.INF:
					return false
		return true
	var waited: bool = await wait_for.call(both_seen, 45000)
	var a: String = read.call(1).get("id", "")
	var b: String = read.call(2).get("id", "")
	if not waited:
		printerr("FAIL two_player_smoke not every peer sees both players: server %s, A %s, B %s"
				% [read.call(0), read.call(1), read.call(2)])
		fail += 1
	else:
		await wait_for.call(func() -> bool: return false, 500)  # let spawn landing settle
		var start: Vector2 = seen.call(1, a)
		var b_start: Vector2 = seen.call(2, a)
		# Walk until A has moved 4 px; a wall, water or the other player may
		# block a way, so try each in turn.
		var moved := false
		for action in ["ui_right", "ui_left", "ui_down", "ui_up"]:
			var walk := FileAccess.open(outs[1] + ".walk", FileAccess.WRITE)
			walk.store_string(action)
			walk.close()
			moved = await wait_for.call(func() -> bool:
				var own: Vector2 = seen.call(1, a)
				return own != Vector2.INF and own.distance_to(start) >= 4.0, 1500)
			DirAccess.remove_absolute(outs[1] + ".walk")
			if moved:
				break
		if not moved:
			printerr("FAIL two_player_smoke player %s did not move from %s in any direction: A %s"
					% [a, start, read.call(1)])
			fail += 1
		else:
			# Once A stops, both other peers see it where A has it.
			var synced := func() -> bool:
				var own: Vector2 = seen.call(1, a)
				return own != Vector2.INF and own.distance_to(seen.call(0, a)) < 1.0 \
						and own.distance_to(seen.call(2, a)) < 1.0 and own.distance_to(b_start) >= 4.0
			if not await wait_for.call(synced, 5000):
				printerr("FAIL two_player_smoke A %s is at %s on A, %s on the server, %s on B (was %s on B)"
						% [a, seen.call(1, a), seen.call(0, a), seen.call(2, a), b_start])
				fail += 1
		for i in 3:
			var errors: Array = read.call(i).get("errors", [])
			if not errors.is_empty():
				printerr("FAIL two_player_smoke peer %s logged errors: %s" % [i, errors])
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
	if fail == 0:
		print("PASS test_two_player_smoke (%s walked, seen by server and %s)" % [a, b])
	return fail
