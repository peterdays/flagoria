extends "res://tests/helpers/test_helpers.gd"
## Free-form walls and cities during two-player play (#498).

const PROBE := "res://tests/wall_sync_probe.gd"
const SEED := 11


func _test_wall_place_two_players() -> int:
	## A water request leaves wood unchanged. A wall on the castle matches
	## piece, caps and auto junctions on both peers and a late joiner.
	## About 8 s alone; stress runs it at the job's tier.
	print("-- test_wall_place_two_players")
	var session := _open("wall")
	if session.is_empty():
		return 1
	var fail := 0
	var read: Callable = session["read"]
	var launch: Callable = session["launch"]
	var wait_for: Callable = session["wait_for"]
	if not await wait_for.call(func() -> bool: return read.call(0).get("ready", false), 30000):
		printerr("FAIL wall_place_two_players: the host did not start: %s" % read.call(0))
		fail = 1
	else:
		launch.call(false, "wall")
		if not await wait_for.call(func() -> bool: return _wall_placed(read), 25000):
			printerr("FAIL wall_place_two_players: after place host %s client %s"
					% [read.call(0), read.call(1)])
			fail = 1
		else:
			launch.call(false, "watch")
			if not await wait_for.call(func() -> bool:
				return read.call(2).get("ready", false) and _same_built(read.call(2), read.call(0)), 30000):
				printerr("FAIL wall_place_two_players: the late joiner %s host %s"
						% [read.call(2), read.call(0)])
				fail = 1
		_note_errors(read, session, "wall_place_two_players")
		if _any_errors(read, session):
			fail = 1
	await _close(session)
	if fail == 0:
		print("PASS test_wall_place_two_players")
	return fail


func _wall_placed(read: Callable) -> bool:
	var host: Dictionary = read.call(0)
	var client: Dictionary = read.call(1)
	if not client.get("ready", false):
		return false
	if int(client.get("refused_wood", -1)) != 4 or int(client.get("wood", -1)) != 2:
		return false
	if int(host.get("wood", -1)) != 0:
		return false
	if not _same_built(client, host):
		return false
	return _wall_connects(host) and _wall_connects(client)


func _wall_connects(data: Dictionary) -> bool:
	## The new palisade touches stone, so it is not a bare post and it has a collar.
	var walls: Array = data.get("walls", [])
	if walls.size() != 1:
		return false
	var piece := str(walls[0][2])
	var caps := str(walls[0][3])
	return piece.begins_with("PALISADE_") and piece != "PALISADE_POST" and caps != "" \
			and not data.get("autos", []).is_empty()


func _test_city_change_two_players() -> int:
	## A client closes a wall loop around a tower. Both peers and a late
	## joiner share cities keys. Opening one cell drops that city on all three.
	## About 15 s alone; stress runs it at the job's tier.
	print("-- test_city_change_two_players")
	var session := _open("city")
	if session.is_empty():
		return 1
	var fail := 0
	var read: Callable = session["read"]
	var launch: Callable = session["launch"]
	var wait_for: Callable = session["wait_for"]
	if not await wait_for.call(func() -> bool: return read.call(0).get("ready", false), 30000):
		printerr("FAIL city_change_two_players: the host did not start: %s" % read.call(0))
		fail = 1
	else:
		launch.call(false, "city")
		if not await wait_for.call(func() -> bool: return _city_closed(read), 30000):
			printerr("FAIL city_change_two_players: after close host %s client %s"
					% [read.call(0), read.call(1)])
			fail = 1
		else:
			launch.call(false, "watch")
			if not await wait_for.call(func() -> bool:
				return read.call(2).get("ready", false) and _same_cities(read.call(2), read.call(0)) \
						and _same_built(read.call(2), read.call(0)), 30000):
				printerr("FAIL city_change_two_players: the late joiner %s host %s"
						% [read.call(2), read.call(0)])
				fail = 1
			else:
				var gap: Array = read.call(1).get("gap", [])
				if gap.size() < 2:
					printerr("FAIL city_change_two_players: no gap cell")
					fail = 1
				else:
					var open := FileAccess.open(session["outs"][0] + ".open", FileAccess.WRITE)
					open.store_string("%d %d" % [int(gap[0]), int(gap[1])])
					open.close()
					if not await wait_for.call(func() -> bool: return _city_opened(read), 15000):
						printerr("FAIL city_change_two_players: after open host %s client %s joiner %s"
								% [read.call(0), read.call(1), read.call(2)])
						fail = 1
		_note_errors(read, session, "city_change_two_players")
		if _any_errors(read, session):
			fail = 1
	await _close(session)
	if fail == 0:
		print("PASS test_city_change_two_players")
	return fail


func _city_closed(read: Callable) -> bool:
	var host: Dictionary = read.call(0)
	var client: Dictionary = read.call(1)
	if str(client.get("place_error", "")) != "" or not client.get("ready", false):
		return false
	var tower := int(client.get("tower_id", -1))
	if tower <= 0 or int(host.get("tower_id", -1)) != tower:
		return false
	if int(client.get("wood", -1)) != 8:
		return false
	return _has_city(host, tower) and _same_cities(client, host) and _same_built(client, host)


func _city_opened(read: Callable) -> bool:
	var tower := int(read.call(1).get("tower_id", -1))
	if tower <= 0:
		return false
	for i in 3:
		if _has_city(read.call(i), tower):
			return false
	return _same_cities(read.call(1), read.call(0)) and _same_cities(read.call(2), read.call(0)) \
			and _same_built(read.call(1), read.call(0)) and _same_built(read.call(2), read.call(0))


func _has_city(data: Dictionary, tower: int) -> bool:
	for row in data.get("cities", []):
		if int(row[0]) == tower:
			return true
	return false


func _same_cities(a: Dictionary, b: Dictionary) -> bool:
	return _key(a.get("cities", [])) == _key(b.get("cities", [])) and not _key(b.get("cities", [])).is_empty()


func _same_built(a: Dictionary, b: Dictionary) -> bool:
	return _key(a.get("walls", [])) == _key(b.get("walls", [])) \
			and _key(a.get("autos", [])) == _key(b.get("autos", [])) \
			and not _key(b.get("walls", [])).is_empty() \
			and not _key(b.get("autos", [])).is_empty()


func _key(rows: Array) -> String:
	var parts: PackedStringArray = []
	for row in rows:
		parts.append(str(row))
	return "|".join(parts)


func _note_errors(read: Callable, session: Dictionary, label: String) -> void:
	for i in session["outs"].size():
		var data: Dictionary = read.call(i)
		if not data.get("errors", []).is_empty() or str(data.get("place_error", "")) != "":
			printerr("FAIL %s: peer %d errors %s place %s" % [label, i, data.get("errors", []), data.get("place_error", "")])


func _any_errors(read: Callable, session: Dictionary) -> bool:
	for i in session["outs"].size():
		var data: Dictionary = read.call(i)
		if not data.get("errors", []).is_empty() or str(data.get("place_error", "")) != "":
			return true
	return false


func _open(mode: String) -> Dictionary:
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL wall sync found no free UDP port")
		return {}
	var dir := OS.get_user_data_dir().path_join("wall_sync_%s_%d_%d" % [mode, OS.get_process_id(), port])
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var params := _spawn_params(SEED, 0.0)
	var saved := MapSave.save_world(WorldSave.new(params), "test_wall_%s_%d_%d" % [mode, OS.get_process_id(), port])
	if saved["error"] != "":
		printerr("FAIL wall sync could not save the map: %s" % saved["error"])
		return {}
	var outs: Array[String] = []
	var pids: Array[int] = []
	var launch := func(as_host: bool, peer_mode: String) -> void:
		outs.append(dir.path_join("p%d.json" % outs.size()))
		var args: Array = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
				"--script", PROBE, "--", "--port=%d" % port, "--out=" + outs[-1], "--mode=" + peer_mode]
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
	launch.call(true, mode)
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
