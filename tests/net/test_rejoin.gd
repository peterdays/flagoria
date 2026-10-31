extends "res://tests/helpers/test_helpers.gd"
## A rejoining peer sees every death.


func _test_rejoin_sees_every_death() -> int:
	## A joiner's process dies with no goodbye and starts again, so it joins
	## under a new peer id while the server still holds the old one until
	## ENet times it out. Every death the server then deals the new player
	## reaches its own client, followed by the respawn (#171), each time, and
	## nothing meant for the old peer reaches the new one.
	print("-- test_rejoin_sees_every_death")
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL rejoin_sees_every_death found no free UDP port")
		return 1
	var dir := OS.get_user_data_dir().path_join("rejoin_%d_%d" % [OS.get_process_id(), port])
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var pids: Array[int] = []
	var outs: Array[String] = []
	var start := func(extra: Array) -> void:
		var out := dir.path_join("p%d.json" % outs.size())
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"),
				"--script", "res://tests/late_join_probe.gd", "--", "--port=%d" % port, "--out=" + out]
		args.append_array(extra)
		pids.append(OS.create_process(OS.get_executable_path(), args))
		outs.append(out)
	var read := func(i: int) -> Dictionary:
		var text := FileAccess.get_file_as_string(outs[i])
		var data = JSON.parse_string(text) if text != "" else null
		return data if data is Dictionary else {}
	var wait_for := func(cond: Callable, ms: int) -> bool:
		var until := Time.get_ticks_msec() + ms
		while Time.get_ticks_msec() < until and not cond.call():
			await process_frame
		return cond.call()
	var joined := func(i: int) -> bool:
		var s: Dictionary = read.call(i)
		return s.get("origin") != null and s.get("players", {}).has(s.get("id")) \
				and read.call(0).get("players", {}).has(s.get("id"))

	var fail := 0
	start.call(["--host"])
	if not await wait_for.call(func() -> bool: return read.call(0).get("origin") != null, 30000):
		printerr("FAIL rejoin_sees_every_death the host did not start")
		fail += 1
	if fail == 0:
		start.call([])
		if not await wait_for.call(joined.bind(1), 30000):
			printerr("FAIL rejoin_sees_every_death the first joiner did not join: %s" % read.call(1))
			fail += 1
	var old_id: String = read.call(1).get("id", "") if fail == 0 else ""
	if fail == 0:
		OS.kill(pids[1])
		pids[1] = 0
		start.call([])
		if not await wait_for.call(joined.bind(2), 30000):
			printerr("FAIL rejoin_sees_every_death the restarted joiner did not join: %s" % read.call(2))
			fail += 1
	if fail == 0:
		var new_id: String = read.call(2)["id"]
		var stale: bool = read.call(0).get("players", {}).has(old_id)
		for k in range(1, 4):
			FileAccess.open(outs[0] + ".kill", FileAccess.WRITE).store_string(str(k))
			var seen := func() -> bool:
				var own: Dictionary = read.call(2)
				return own.get("deaths", 0) >= k and own.get("players", {}).get(new_id, {}).get("respawns", 0) >= k
			if not await wait_for.call(seen, 10000):
				var own: Dictionary = read.call(2)
				printerr("FAIL rejoin_sees_every_death death %d: its own client saw %s deaths and %s respawns, the server %s respawns"
						% [k, own.get("deaths"), own.get("players", {}).get(new_id, {}).get("respawns"),
						read.call(0).get("players", {}).get(new_id, {}).get("respawns")])
				fail += 1
				break
		if fail == 0 and not read.call(2).get("errors", []).is_empty():
			printerr("FAIL rejoin_sees_every_death the restarted joiner logged errors, so traffic for the old peer reached it: %s"
					% [read.call(2)["errors"]])
			fail += 1
		if fail == 0:
			print("PASS test_rejoin_sees_every_death (3 deaths and respawns; old peer %s)"
					% ("still held at the first" if stale else "already gone"))

	for out in outs:
		FileAccess.open(out + ".stop", FileAccess.WRITE).close()
	await wait_for.call(func() -> bool:
		for pid in pids:
			if pid > 0 and OS.is_process_running(pid):
				return false
		return true, 10000)
	for pid in pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	_remove_dir(dir)
	return fail
