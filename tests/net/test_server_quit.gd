extends "res://tests/helpers/test_helpers.gd"
## SIGTERM stops a dedicated server cleanly, and the joined client returns
## to the main menu.


func _test_server_quit() -> int:
	## Start `-- --server`, join with add_player_joined, then kill -TERM.
	## The server exits 0 after one "Dedicated server stopped." line, and the
	## client's main menu is back within 6 s of SIGTERM. Time cost: ~4–8 s
	## in verify, and about that again for each netcode-stress run.
	print("-- test_server_quit")
	await process_frame
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL server_quit found no free UDP port")
		return 1
	var dir := OS.get_user_data_dir().path_join("server_quit_%d_%d" % [OS.get_process_id(), port])
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var log_path := dir.path_join("server.log")
	var status_path := dir.path_join("client.txt")
	var server_pid := OS.create_process(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--log-file", log_path, "--", "--server", "--port=%d" % port]
	)
	if server_pid <= 0:
		printerr("FAIL server_quit could not start the server")
		return 1
	var client_pid := OS.create_process(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/server_quit_probe.gd", "--",
			"--port=%d" % port, "--status=%s" % status_path]
	)
	if client_pid <= 0:
		OS.execute("kill", ["-TERM", str(server_pid)])
		printerr("FAIL server_quit could not start the client")
		return 1
	var fail := 0
	var joined := await _wait_status(status_path, "joined", 20000)
	if not joined:
		printerr("FAIL server_quit client did not join")
		fail = 1
	else:
		var term := OS.execute("kill", ["-TERM", str(server_pid)])
		if term != 0:
			printerr("FAIL server_quit kill -TERM returned %s" % term)
			fail = 1
		var server_done := await _wait_exit(server_pid, 8000)
		var code := OS.get_process_exit_code(server_pid)
		var log_text := FileAccess.get_file_as_string(log_path)
		var stops := log_text.split("Dedicated server stopped.", false).size() - 1
		if not server_done or code != 0:
			printerr("FAIL server_quit server exit %s running=%s" % [code, OS.is_process_running(server_pid)])
			fail = 1
		if stops != 1:
			printerr("FAIL server_quit shutdown log count %s" % stops)
			fail = 1
		var menu := await _wait_status(status_path, "menu", 6000)
		if not menu or not await _wait_exit(client_pid, 3000) or OS.get_process_exit_code(client_pid) != 0:
			printerr("FAIL server_quit client did not return to the main menu")
			fail = 1
	if OS.is_process_running(server_pid):
		OS.kill(server_pid)
	if OS.is_process_running(client_pid):
		OS.kill(client_pid)
	_remove_dir(dir)
	if fail == 0:
		print("PASS test_server_quit")
	return fail


func _wait_status(path: String, text: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(path) and text in FileAccess.get_file_as_string(path):
			return true
		await process_frame
	return false


func _wait_exit(pid: int, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if not OS.is_process_running(pid):
			return true
		await process_frame
	return not OS.is_process_running(pid)
