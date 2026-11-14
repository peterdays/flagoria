extends SceneTree
## One peer of a land-score session (#279).
## Host: --host --save --port --out. Client: --port --out --mode.
## The host scores city land. A ".drop" file hands the host castle to neutral.


var _errors := _ErrorLog.new()
var _dropped := false
var _client_tick_same := true


class _ErrorLog extends Logger:
	var lines: Array[String] = []
	var _lock := Mutex.new()

	func _log_error(function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_lock.lock()
		if lines.size() < 5:
			lines.append("%s: %s" % [function, rationale if rationale != "" else code])
		_lock.unlock()

	func snapshot() -> Array[String]:
		_lock.lock()
		var copy := lines.duplicate()
		_lock.unlock()
		return copy


func _initialize() -> void:
	OS.add_logger(_errors)
	call_deferred("_run")


func _run() -> void:
	var port := 0
	var save := ""
	var out := ""
	var host := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--save="):
			save = arg.trim_prefix("--save=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg == "--host":
			host = true
	if port == 0 or out == "" or (host and save == "") or change_scene_to_file("res://flagoria_main.tscn") != OK:
		printerr("land_score_probe: needs --port, --out, --save with --host, and the main scene")
		quit(1)
		return
	await process_frame
	await process_frame
	var main = current_scene
	main.get_node("CanvasLayer2/MainMenu").hide()
	if host:
		var map_gen = root.get_node("MapGen")
		var error: String = map_gen.load_map_inputs(save)
		if error != "" or main.setup_server(map_gen.params.duplicate_params(), port) != OK:
			printerr("land_score_probe: could not host %s: %s" % [save, error])
			quit(1)
			return
		main.add_player(1)
		main.get_node("Discovery").set_physics_process(false)
		_park_mobs(main)
	else:
		main.add_player_joined(port)
	var world = main.get_node("World/worldMap")
	var checked_client := false
	var deadline := Time.get_ticks_msec() + 60000
	var next_write := 0
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(out + ".stop"):
		if main.multiplayer == null:
			break
		var me: Node2D = main.get_node_or_null("World/" + str(main.multiplayer.get_unique_id()))
		if host and not _dropped and FileAccess.file_exists(out + ".drop"):
			_dropped = true
			_drop_host_castle(main, world)
		if not host and not checked_client and main.world_params != null and me != null:
			checked_client = true
			var points: Points = main.get_node("Points")
			var before: int = points.total_of(1)
			main.get_node("World/LandScore").tick()
			_client_tick_same = points.total_of(1) == before
		if Time.get_ticks_msec() >= next_write:
			_write(out, main, world, me)
			next_write = Time.get_ticks_msec() + 100
		await process_frame
	var fin: Node2D = null
	if main.multiplayer != null:
		fin = main.get_node_or_null("World/" + str(main.multiplayer.get_unique_id()))
	_write(out, main, world, fin)
	quit(0)


func _drop_host_castle(main, world) -> void:
	var placed: Dictionary = world.placed_structures()
	var castle := -1
	for id in placed:
		if str(placed[id]["name"]) == "castle" and int(placed[id]["owner"]) == 1:
			castle = int(id)
			break
	if castle < 0:
		return
	world._structures.set_owner(castle, StructurePlacer.OWNER_NEUTRAL)
	var capture: TowerCapture = main.get_node("World/TowerCapture")
	capture.receive_capture_state.rpc(capture.capture_snapshot())
	main.get_node("World/LandScore").tick()


func _park_mobs(main) -> void:
	for node in main.get_node("World/Mobs").get_children():
		if node is Mob:
			node.global_position = Vector2(100000, 100000)


func _write(out: String, main, world, me: Node2D) -> void:
	if out == "" or main == null:
		return
	var points := {}
	var land := {}
	var board := []
	if main.world_params != null:
		var scores: Points = main.get_node("Points")
		var counts: Dictionary = main.get_node("World/LandScore").covered_counts()
		var ids := {1: true}
		for node in main.get_node("World").get_children():
			if str(node.name).is_valid_int():
				ids[int(str(node.name))] = true
		for peer_id in ids:
			points[str(peer_id)] = scores.total_of(int(peer_id))
			land[str(peer_id)] = int(counts.get(int(peer_id), 0))
		var panel: ScoreboardPanel = main.get_node("CanvasLayer1/ScoreboardPanel")
		for row in panel.sorted_rows():
			board.append([int(row[0]), int(row[1])])
	var file := FileAccess.open(out + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"id": str(main.multiplayer.get_unique_id()) if main.multiplayer != null else "",
		"ready": main.world_params != null and me != null,
		"dropped": _dropped,
		"client_tick_same": _client_tick_same,
		"points": points,
		"land": land,
		"board": board,
		"errors": _errors.snapshot(),
	}))
	file.close()
	DirAccess.rename_absolute(out + ".tmp", out)
