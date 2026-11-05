extends SceneTree
## Joins a dedicated server on --port=N, kills that server, and checks the
## client returns to the main menu via server_disconnected (#348).
## Printed by test_join_fail_host_quits.

var _fail := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if not ok:
		printerr("join_fail_probe: FAIL %s" % what)
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var port := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
	if port == 0:
		printerr("join_fail_probe: needs --port=N")
		quit(1)
		return
	var pid := OS.create_process(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--", "--server", "--port=%d" % port]
	)
	if pid <= 0:
		printerr("join_fail_probe: could not start server")
		quit(1)
		return
	if change_scene_to_file("res://flagoria_main.tscn") != OK:
		printerr("join_fail_probe: could not load main scene")
		OS.kill(pid)
		quit(1)
		return
	await _frames(3)
	var main = current_scene
	main.get_node("CanvasLayer2/MainMenu").hide()
	main.get_node("CanvasLayer1").show()
	main.add_player_joined(port)
	var world: Node = main.get_node("World")
	var client_id := 0
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and OS.is_process_running(pid):
		client_id = main.multiplayer.get_unique_id()
		if main.world_params != null and world.has_node(str(client_id)):
			break
		await process_frame
	_check(world.has_node(str(client_id)), "never joined server before kill")
	if _fail > 0:
		OS.kill(pid)
		quit(1)
		return
	OS.kill(pid)
	deadline = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		main = current_scene
		if main == null:
			continue
		var menu = main.get_node_or_null("CanvasLayer2/MainMenu")
		if menu != null and menu.visible:
			break
	main = current_scene
	var menu2 = main.get_node_or_null("CanvasLayer2/MainMenu") if main else null
	_check(menu2 != null and menu2.visible, "main menu not visible after host quit")
	_check(main.get_node_or_null("CanvasLayer1") == null
			or not main.get_node("CanvasLayer1").visible,
			"HUD still visible after host quit")
	if _fail == 0:
		print("JOIN_FAIL_PROBE_OK")
	quit(0 if _fail == 0 else 1)
