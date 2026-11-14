extends "res://tests/helpers/test_helpers.gd"
## Host land totals on both peers and a late joiner (#279). Seed 11.
## Discovery is off in the probe, so the total is the land count. Handing
## the host castle to neutral drops that total on every peer.

const PROBE := "res://tests/land_score_probe.gd"
const SEED := 11


func _test_land_score_two_players() -> int:
	## The host castle's covered cells match on the client and a late joiner,
	## including the scoreboard row. Neutralizing that castle removes the
	## host's land on all three. About 6 s alone; stress runs it at the job's
	## tier.
	print("-- test_land_score_two_players")
	var session := _open()
	if session.is_empty():
		return 1
	var fail := 0
	var read: Callable = session["read"]
	var launch: Callable = session["launch"]
	var wait_for: Callable = session["wait_for"]
	if not await wait_for.call(func() -> bool: return _scoring(read.call(0)), 20000):
		printerr("FAIL land_score_two_players: the host did not score: %s" % read.call(0))
		fail = 1
	else:
		launch.call(false)
		if not await wait_for.call(func() -> bool: return _matched(read.call(1), read.call(0)), 20000):
			printerr("FAIL land_score_two_players: client %s host %s" % [read.call(1), read.call(0)])
			fail = 1
		else:
			launch.call(false)
			if not await wait_for.call(func() -> bool:
				return read.call(2).get("ready", false) and _matched(read.call(2), read.call(0)) \
						and _matched(read.call(1), read.call(0)), 20000):
				printerr("FAIL land_score_two_players: joiner %s host %s" % [read.call(2), read.call(0)])
				fail = 1
			else:
				var before := int(read.call(0).get("points", {}).get("1", -1))
				var drop := FileAccess.open(session["outs"][0] + ".drop", FileAccess.WRITE)
				drop.store_string("drop")
				drop.close()
				if not await wait_for.call(func() -> bool: return _dropped(read, before), 15000):
					printerr("FAIL land_score_two_players: after the loss host %s client %s joiner %s"
							% [read.call(0), read.call(1), read.call(2)])
					fail = 1
		for i in session["outs"].size():
			var data: Dictionary = read.call(i)
			if not data.get("errors", []).is_empty() or data.get("client_tick_same", true) != true:
				printerr("FAIL land_score_two_players: peer %d errors %s client tick %s"
						% [i, data.get("errors", []), data.get("client_tick_same", true)])
				fail = 1
	await _close(session)
	if fail == 0:
		print("PASS test_land_score_two_players")
	return fail


func _scoring(data: Dictionary) -> bool:
	if not data.get("ready", false):
		return false
	var points: Dictionary = data.get("points", {})
	var land: Dictionary = data.get("land", {})
	var total := int(points.get("1", -1))
	return total > 0 and total == int(land.get("1", -2)) and _board_has(data, 1, total)


func _matched(data: Dictionary, host: Dictionary) -> bool:
	var host_total := int(host.get("points", {}).get("1", -1))
	return host_total > 0 and _same(data, host)


func _same(data: Dictionary, host: Dictionary) -> bool:
	## Points, local land counts, and the host's scoreboard row agree.
	## A zero host total is allowed: neutralizing the castle is that case.
	if not data.get("ready", false) or not data.get("client_tick_same", false):
		return false
	var mine: Dictionary = data.get("points", {})
	var theirs: Dictionary = host.get("points", {})
	if theirs.is_empty() or mine.size() != theirs.size():
		return false
	for peer_id in theirs:
		if int(mine.get(str(peer_id), -1)) != int(theirs[peer_id]):
			return false
		if int(data.get("land", {}).get(str(peer_id), -1)) != int(host.get("land", {}).get(str(peer_id), -2)):
			return false
	return _board_has(data, 1, int(theirs.get("1", -1)))


func _dropped(read: Callable, before: int) -> bool:
	var host: Dictionary = read.call(0)
	if not host.get("dropped", false):
		return false
	var now := int(host.get("points", {}).get("1", before))
	if now >= before or now != int(host.get("land", {}).get("1", -1)):
		return false
	if not _board_has(host, 1, now):
		return false
	return _same(read.call(1), host) and _same(read.call(2), host)


func _board_has(data: Dictionary, peer: int, total: int) -> bool:
	for row in data.get("board", []):
		if int(row[0]) == peer and int(row[1]) == total:
			return true
	return false


func _open() -> Dictionary:
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL land score sync found no free UDP port")
		return {}
	var dir := OS.get_user_data_dir().path_join("land_score_%d_%d" % [OS.get_process_id(), port])
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var params := _spawn_params(SEED, 0.0)
	var saved := MapSave.save_world(WorldSave.new(params), "test_land_score_%d_%d" % [OS.get_process_id(), port])
	if saved["error"] != "":
		printerr("FAIL land score sync could not save the map: %s" % saved["error"])
		return {}
	var outs: Array[String] = []
	var pids: Array[int] = []
	var launch := func(as_host: bool) -> void:
		outs.append(dir.path_join("p%d.json" % outs.size()))
		var args: Array = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
				"--script", PROBE, "--", "--port=%d" % port, "--out=" + outs[-1]]
		if as_host:
			args.append("--host")
			args.append("--save=" + ProjectSettings.globalize_path(saved["path"]))
		pids.append(OS.create_process(OS.get_executable_path(), args))
	var read := func(i: int) -> Dictionary:
		if i >= outs.size() or not FileAccess.file_exists(outs[i]):
			return {}
		var data = JSON.parse_string(FileAccess.get_file_as_string(outs[i]))
		return data if data is Dictionary else {}
	var wait_for := func(cond: Callable, ms: int) -> bool:
		var until := Time.get_ticks_msec() + ms
		while Time.get_ticks_msec() < until and not cond.call():
			await process_frame
		return cond.call()
	launch.call(true)
	return {
		"dir": dir, "outs": outs, "pids": pids, "saved": saved["path"],
		"launch": launch, "read": read, "wait_for": wait_for,
	}


func _close(session: Dictionary) -> void:
	if session.is_empty():
		return
	for out in session["outs"]:
		FileAccess.open(out + ".stop", FileAccess.WRITE).close()
	var wait: Callable = session["wait_for"]
	await wait.call(func() -> bool:
		for pid in session["pids"]:
			if OS.is_process_running(pid):
				return false
		return true, 10000)
	for pid in session["pids"]:
		if OS.is_process_running(pid):
			OS.kill(pid)
	_remove_dir(session["dir"])
	DirAccess.remove_absolute(session["saved"])
