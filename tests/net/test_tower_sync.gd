extends "res://tests/helpers/test_helpers.gd"
## Towers, capture progress and flags-held points during two-player play (#497).

const PROBE := "res://tests/tower_sync_probe.gd"
const SEED := 7


func _test_tower_place_two_players() -> int:
	## Water request leaves wood unchanged; a land tower and the flags-held
	## totals match on both peers and a late joiner. About 5 s alone; stress
	## runs it at the job's tier.
	print("-- test_tower_place_two_players")
	var session := _open("place")
	if session.is_empty():
		return 1
	var fail := 0
	var read: Callable = session["read"]
	var launch: Callable = session["launch"]
	var wait_for: Callable = session["wait_for"]
	if not await wait_for.call(func() -> bool: return read.call(0).get("ready", false), 30000):
		printerr("FAIL tower_place_two_players: the host did not start: %s" % read.call(0))
		fail = 1
	else:
		launch.call(false, "place")
		if not await wait_for.call(func() -> bool: return read.call(1).get("ready", false), 30000):
			printerr("FAIL tower_place_two_players: the client did not join: %s" % read.call(1))
			fail = 1
		elif not await wait_for.call(func() -> bool: return _placed(read), 20000):
			printerr("FAIL tower_place_two_players: after place host %s client %s"
					% [read.call(0), read.call(1)])
			fail = 1
		else:
			launch.call(false, "watch")
			if not await wait_for.call(func() -> bool:
				return read.call(2).get("ready", false) and _same_place(read.call(2), read.call(0)) \
						and _same_points(read.call(2), read.call(0)), 30000):
				printerr("FAIL tower_place_two_players: the late joiner %s host %s"
						% [read.call(2), read.call(0)])
				fail = 1
		for i in session["outs"].size():
			if not read.call(i).get("errors", []).is_empty() or str(read.call(i).get("place_error", "")) != "":
				printerr("FAIL tower_place_two_players: peer %d errors %s place %s"
						% [i, read.call(i).get("errors", []), read.call(i).get("place_error", "")])
				fail = 1
	await _close(session)
	if fail == 0:
		print("PASS test_tower_place_two_players")
	return fail


func _placed(read: Callable) -> bool:
	var host: Dictionary = read.call(0)
	var client: Dictionary = read.call(1)
	if int(client.get("refused_wood", -1)) != 10 or int(client.get("wood", -1)) != 0:
		return false
	if int(host.get("wood", -1)) != 0:
		return false
	if not _same_place(client, host):
		return false
	var builder := _peer_id(client)
	return builder > 1 and _tower_count(host) == 1 and _owner_named(host, "tower_wood") == builder \
			and _owner_named(host, "castle") == 1 and _flag_points(host, builder) and _flag_points(client, builder)


func _test_tower_capture_two_players() -> int:
	## Seed 7. Eight ticks of 0.5 s leave progress 4 and the builder as owner;
	## two more hand the tower to the host. A joiner in between matches.
	## About 5 s alone; stress runs it at the job's tier.
	print("-- test_tower_capture_two_players")
	var session := _open("capture")
	if session.is_empty():
		return 1
	var fail := 0
	var read: Callable = session["read"]
	var launch: Callable = session["launch"]
	var wait_for: Callable = session["wait_for"]
	if not await wait_for.call(func() -> bool: return read.call(0).get("ready", false), 30000):
		printerr("FAIL tower_capture_two_players: the host did not start: %s" % read.call(0))
		fail = 1
	else:
		launch.call(false, "capture")
		if not await wait_for.call(func() -> bool:
			var builder := _peer_id(read.call(1))
			return read.call(1).get("aside", false) and builder > 1 \
					and _owner_named(read.call(0), "tower_wood") == builder \
					and _same_place(read.call(1), read.call(0)), 30000):
			printerr("FAIL tower_capture_two_players: tower was not built: host %s client %s"
					% [read.call(0), read.call(1)])
			fail = 1
		else:
			var cap := FileAccess.open(session["outs"][0] + ".capture", FileAccess.WRITE)
			cap.store_string("8,0.5")
			cap.close()
			if not await wait_for.call(func() -> bool:
				var builder := _peer_id(read.call(1))
				return _progress_is(read.call(0), 4.0) and _progress_is(read.call(1), 4.0) \
						and _owner_named(read.call(0), "tower_wood") == builder \
						and _owner_named(read.call(1), "tower_wood") == builder, 15000):
				printerr("FAIL tower_capture_two_players: after 8 ticks host %s client %s"
						% [read.call(0), read.call(1)])
				fail = 1
			else:
				launch.call(false, "watch")
				if not await wait_for.call(func() -> bool:
					var builder := _peer_id(read.call(1))
					return read.call(2).get("ready", false) and _progress_is(read.call(2), 4.0) \
							and _owner_named(read.call(2), "tower_wood") == builder \
							and _same_place(read.call(2), read.call(0)), 30000):
					printerr("FAIL tower_capture_two_players: late joiner progress %s host %s"
							% [read.call(2), read.call(0)])
					fail = 1
				else:
					var more := FileAccess.open(session["outs"][0] + ".capture_more", FileAccess.WRITE)
					more.store_string("2,0.5")
					more.close()
					if not await wait_for.call(func() -> bool: return _captured(read), 15000):
						printerr("FAIL tower_capture_two_players: after capture host %s client %s joiner %s"
								% [read.call(0), read.call(1), read.call(2)])
						fail = 1
		for i in session["outs"].size():
			if not read.call(i).get("errors", []).is_empty() or str(read.call(i).get("place_error", "")) != "":
				printerr("FAIL tower_capture_two_players: peer %d errors %s place %s"
						% [i, read.call(i).get("errors", []), read.call(i).get("place_error", "")])
				fail = 1
	await _close(session)
	if fail == 0:
		print("PASS test_tower_capture_two_players")
	return fail


func _captured(read: Callable) -> bool:
	for i in 3:
		var data: Dictionary = read.call(i)
		if not _progress_is(data, 0.0) or _owner_named(data, "tower_wood") != 1:
			return false
		if _owner_named(data, "castle") != 1:
			return false
	return _same_place(read.call(1), read.call(0)) and _same_place(read.call(2), read.call(0))


func _progress_is(data: Dictionary, want: float) -> bool:
	var id := _id_named(data, "tower_wood")
	if id < 0:
		return false
	for row in data.get("capture", []):
		if int(row[0]) == id:
			return is_equal_approx(float(row[3]), want) and int(row[1]) == _owner_named(data, "tower_wood")
	return false


func _same_place(a: Dictionary, b: Dictionary) -> bool:
	return _keys(a) == _keys(b) and not _keys(a).is_empty()

func _peer_id(data: Dictionary) -> int:
	return int(str(data.get("id", "0")))

func _flag_points(data: Dictionary, builder: int) -> bool:
	## The host owns its castle. The builder owns a castle and the new tower.
	var scores: Dictionary = data.get("points", {})
	return int(scores.get("1", -1)) == Points.FLAGS_HELD_POINTS \
			and int(scores.get(str(builder), -1)) == Points.FLAGS_HELD_POINTS * 2

func _same_points(a: Dictionary, b: Dictionary) -> bool:
	var left: Dictionary = a.get("points", {})
	var right: Dictionary = b.get("points", {})
	if right.is_empty():
		return false
	for peer_id in right:
		if int(left.get(str(peer_id), -1)) != int(right[peer_id]):
			return false
	return true

func _keys(data: Dictionary) -> Array:
	var rows := []
	for entry in data.get("placements", []):
		rows.append("%s:%s:%s:%s:%s" % [entry[0], entry[1], entry[2], entry[3], entry[4]])
	rows.sort()
	return rows

func _id_named(data: Dictionary, structure_name: String) -> int:
	for entry in data.get("placements", []):
		if str(entry[1]) == structure_name:
			return int(entry[0])
	return -1

func _owner_named(data: Dictionary, structure_name: String) -> int:
	for entry in data.get("placements", []):
		if str(entry[1]) == structure_name:
			return int(entry[2])
	return -1

func _tower_count(data: Dictionary) -> int:
	var n := 0
	for entry in data.get("placements", []):
		if str(entry[1]) == "tower_wood":
			n += 1
	return n

func _open(mode: String) -> Dictionary:
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL tower sync found no free UDP port")
		return {}
	var dir := OS.get_user_data_dir().path_join("tower_sync_%s_%d_%d" % [mode, OS.get_process_id(), port])
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var params := _spawn_params(SEED, 0.0)
	var saved := MapSave.save_world(WorldSave.new(params), "test_tower_%s_%d_%d" % [mode, OS.get_process_id(), port])
	if saved["error"] != "":
		printerr("FAIL tower sync could not save the map: %s" % saved["error"])
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
