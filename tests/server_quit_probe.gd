extends SceneTree
## Joins a dedicated server with add_player_joined, then waits until SIGTERM
## brings the main menu back. The test starts the server and sends SIGTERM.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var port := 0
	var status_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--status="):
			status_path = arg.trim_prefix("--status=")
	if port == 0 or status_path == "":
		printerr("server_quit_probe: needs --port=N --status=PATH")
		quit(1)
		return
	if change_scene_to_file("res://flagoria_main.tscn") != OK:
		printerr("server_quit_probe: cannot load the main scene")
		quit(1)
		return
	for _i in 3:
		await process_frame
	var main = current_scene
	main.add_player_joined(port)
	var world: Node = main.get_node("World")
	var deadline := Time.get_ticks_msec() + 20000
	var client_id := 0
	while Time.get_ticks_msec() < deadline:
		client_id = main.multiplayer.get_unique_id()
		if main.world_params != null and client_id != 1 and world.has_node(str(client_id)):
			break
		await process_frame
	if not world.has_node(str(client_id)):
		printerr("server_quit_probe: did not join")
		quit(1)
		return
	var status := FileAccess.open(status_path, FileAccess.WRITE)
	status.store_string("joined\n")
	status.close()
	# Longer than the test's 6 s menu bound, so a slow parent can still
	# send SIGTERM before this probe gives up.
	deadline = Time.get_ticks_msec() + 12000
	var menu: Node = null
	while Time.get_ticks_msec() < deadline:
		await process_frame
		main = current_scene
		if main == null:
			continue
		menu = main.get_node_or_null("CanvasLayer2/MainMenu")
		var hud := main.get_node_or_null("CanvasLayer1")
		if menu != null and menu.visible and (hud == null or not hud.visible):
			var done := FileAccess.open(status_path, FileAccess.READ_WRITE)
			done.seek_end()
			done.store_string("menu\n")
			done.close()
			print("SERVER_QUIT_MENU_OK")
			quit(0)
			return
	printerr("server_quit_probe: main menu not back within 12 s")
	quit(1)
