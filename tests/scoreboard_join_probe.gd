extends SceneTree
## Client for the points scoreboard drive: joins the host and reports when two
## players are in the world.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var out := ""
	var port := 9786
	var min_players := 2
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--min-players="):
			min_players = maxi(2, arg.trim_prefix("--min-players=").to_int())
	if out == "" or change_scene_to_file("res://flagoria_main.tscn") != OK:
		printerr("scoreboard_join_probe: needs --out and the main scene")
		quit(1)
		return
	await process_frame
	await process_frame
	var main = current_scene
	main.host_port = port
	var join := main.get_node("CanvasLayer2/MainMenu/MarginContainer/VBoxContainer/JoinButton")
	main.get_node("CanvasLayer2/MainMenu").hide()
	main.get_node("CanvasLayer1").show()
	join.pressed.emit()
	var until := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < until:
		if main.get_node("World").get_child_count() >= min_players and main.world_params != null:
			break
		await process_frame
	var ready := main.get_node("World").get_child_count() >= min_players
	_write(out, {"ready": ready, "players": _player_names(main)})
	if not ready:
		quit(1)
		return
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(out + ".stop"):
		await process_frame
	quit(0)


func _player_names(main: Node) -> PackedStringArray:
	var names := PackedStringArray()
	for child in main.get_node("World").get_children():
		names.append(child.name)
	names.sort()
	return names


func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))