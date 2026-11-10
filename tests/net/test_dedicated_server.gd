extends "res://tests/helpers/test_helpers.gd"
## Joining a dedicated server, and its params file.


func _test_dedicated_server_join() -> int:
	## Boot `-- --server` as a second headless process, join it through the
	## main scene's normal Join path, and check that the client gets the map
	## params and its own player, and that the host spawned no local player.
	print("-- test_dedicated_server_join")
	var timeout_ms := 30000
	await process_frame
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL dedicated_server_join found no free UDP port")
		return 1
	var pid := OS.create_process(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--server", "--port=%d" % port]
	)
	if pid <= 0:
		printerr("FAIL dedicated_server_join could not start the server process")
		return 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var fail := 0
	var client_id := 0
	var world: Node = scene.get_node("World")
	if scene.get_path() != NodePath("/root/Flagoria"):
		printerr("FAIL dedicated_server_join scene at %s, not /root/Flagoria" % scene.get_path())
		fail += 1
	else:
		# ENet retries the handshake, so joining before the server binds is fine.
		scene.add_player_joined(port)
		var deadline := Time.get_ticks_msec() + timeout_ms
		while Time.get_ticks_msec() < deadline and OS.is_process_running(pid):
			client_id = scene.multiplayer.get_unique_id()
			var params_ok: bool = scene.world_params != null and scene.world_params.altitude_seed != 0
			if params_ok and world.has_node(str(client_id)):
				break
			await process_frame
		var params: MapGenParams = scene.world_params
		if not OS.is_process_running(pid):
			printerr("FAIL dedicated_server_join server process exited early")
			fail += 1
		elif params == null or params.altitude_seed == 0 or params.items_seed == 0:
			printerr("FAIL dedicated_server_join no map params from server within %s ms" % timeout_ms)
			fail += 1
		elif not world.has_node(str(client_id)):
			printerr("FAIL dedicated_server_join server did not spawn player %s" % client_id)
			fail += 1
		elif world.has_node("1"):
			printerr("FAIL dedicated_server_join server spawned a local player")
			fail += 1

	OS.kill(pid)
	scene.enet_peer.close()
	scene.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	scene.queue_free()
	if fail == 0:
		print("PASS test_dedicated_server_join (client %s)" % client_id)
	return fail


func _test_dedicated_server_params_file() -> int:
	## `-- --server --params <file>` hosts the map in that save: a client that
	## joins gets exactly its params. The file is a byte copy of the save, the
	## shape of a mounted params file. A missing file stops the server with
	## exit 1 before it listens. Both server runs have a hard `timeout`.
	print("-- test_dedicated_server_params_file")
	var fail := 0
	var exe := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	await process_frame
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL dedicated_server_params_file found no free UDP port")
		return 1
	var out := []
	var code := OS.execute("timeout", ["-k", "5", "30", exe, "--headless", "--path", project,
		"--", "--server", "--port=%d" % port, "--params=user://no_such_save.json"], out, true)
	if code != 1 or not "no map save" in "".join(out):
		printerr("FAIL dedicated_server_params_file missing file: exit %s, want 1 and 'no map save'" % code)
		fail += 1

	var params := MapGenParams.make_defaults()
	params.altitude_seed = 2201
	params.moisture_seed = 2202
	params.temperature_seed = 2203
	params.items_seed = 2204
	params.biome_seed = 2205
	params.water_max_alt = 0.125
	var saved := MapSave.save_map(params, "test_dedicated_server_params")
	if saved["error"] != "":
		printerr("FAIL dedicated_server_params_file save: %s" % saved["error"])
		return fail + 1
	# The docker params mount is this file copied somewhere else as bytes.
	# `timeout` forwards the TERM below to the server and kills it after 90 s
	# whatever happens to this run.
	var mounted := OS.get_temp_dir().path_join("flagoria_ds_params_%d.json" % OS.get_process_id())
	var raw := FileAccess.get_file_as_bytes(saved["path"])
	var handle := FileAccess.open(mounted, FileAccess.WRITE)
	if handle == null or raw.size() < 2 or raw[0] != 0x1f or raw[1] != 0x8b:
		printerr("FAIL dedicated_server_params_file save is not a gzip file to mount")
		DirAccess.remove_absolute(saved["path"])
		return fail + 1
	handle.store_buffer(raw)
	handle.close()
	var pid := OS.create_process("timeout", ["-k", "5", "90", exe, "--headless", "--path", project,
		"--", "--server", "--port=%d" % port, "--params=" + mounted])
	if pid <= 0:
		printerr("FAIL dedicated_server_params_file could not start the server process")
		DirAccess.remove_absolute(saved["path"])
		DirAccess.remove_absolute(mounted)
		return fail + 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.add_player_joined(port)
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and OS.is_process_running(pid):
		if scene.world_params != null and scene.world_params.altitude_seed != 0:
			break
		await process_frame
	var got: MapGenParams = scene.world_params
	if got == null or got.to_dict() != params.to_dict():
		printerr("FAIL dedicated_server_params_file client got %s, want %s" % [
			got.to_dict() if got != null else null, params.to_dict()])
		fail += 1
	OS.execute("kill", ["-TERM", str(pid)])
	scene.enet_peer.close()
	scene.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	scene.queue_free()
	DirAccess.remove_absolute(saved["path"])
	DirAccess.remove_absolute(mounted)
	if fail == 0:
		print("PASS test_dedicated_server_params_file")
	return fail
