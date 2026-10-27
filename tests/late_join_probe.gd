extends SceneTree
## One peer of a multi-peer spawn session, run as its own headless process by
## test_spawn_late_join in run_tests.gd.
##   -- --port=N --out=PATH              join localhost:N through the Join path
##   -- --port=N --out=PATH --host       listen host with its own player
##   -- --port=N --out=PATH --dedicated  dedicated server, no player
## Every 100 ms it writes PATH (JSON): its peer id, the spawn point, every
## player's position and respawn count as this peer sees them, the last
## respawn spot its own player was sent and, on the server, the spot it
## picked for each player that joined, how many deaths its own player had
## and the first engine errors this process logged. It quits once PATH.stop exists. The server also kills every player
## in one frame once PATH.kill exists, so they all respawn together, and
## again each time the text in PATH.kill changes.

var _out := ""
var _id := 0
var _picked := {}
var _respawned_at := Vector2.INF
var _origin := Vector2.INF
var _kill_text = null
var _deaths := 0
var _errors := _ErrorLog.new()


class _ErrorLog extends Logger:
	## Keeps the first few errors; Godot may log from any thread.
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
	var mode := "join"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg in ["--host", "--dedicated"]:
			mode = arg.trim_prefix("--")
	if port == 0 or _out == "" or change_scene_to_file("res://flagoria_main.tscn") != OK:
		printerr("late_join_probe: needs --port=N, --out=PATH and the main scene")
		quit(1)
		return
	await process_frame
	await process_frame
	var main = current_scene
	var world: Node = main.get_node("World")
	if mode != "join":
		# The server sets a player's spot before adding it to the tree.
		world.child_entered_tree.connect(func(node: Node) -> void:
			if node is CharacterBody2D:
				_picked[str(node.name)] = [node.position.x, node.position.y])
	if mode == "host":
		main.setup_server(root.get_node("MapGen").params, port)
		main.add_player(1)
	elif mode == "dedicated":
		main.start_dedicated_server(port)
	else:
		main.add_player_joined(port)
	_id = main.multiplayer.get_unique_id()
	var deadline := Time.get_ticks_msec() + 90000
	var next_write := 0
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(_out + ".stop"):
		var me: Node = world.get_node_or_null(str(_id))
		if me and not me.health.respawned.is_connected(_on_respawned):
			me.health.respawned.connect(_on_respawned)
			me.health.health_changed.connect(_on_health_changed)
		if mode != "join" and FileAccess.file_exists(_out + ".kill") \
				and FileAccess.get_file_as_string(_out + ".kill") != _kill_text:
			_kill_text = FileAccess.get_file_as_string(_out + ".kill")
			for child in world.get_children():
				if child is CharacterBody2D:
					child.health.set_health_now(0)
		if Time.get_ticks_msec() >= next_write:
			next_write = Time.get_ticks_msec() + 100
			_write(main, world)
		await process_frame
	_write(main, world)
	quit(0)


func _on_respawned(at: Vector2) -> void:
	_respawned_at = at


func _on_health_changed(current: int, _maximum: int) -> void:
	if current == 0:
		_deaths += 1


func _write(main: Node, world: Node) -> void:
	if _origin == Vector2.INF and main.world_params != null:
		var map = world.get_node("worldMap")
		_origin = map.map_to_local(map.resolve_player_spawn())
	var players := {}
	for child in world.get_children():
		if child is CharacterBody2D:
			players[str(child.name)] = {
				"pos": [child.position.x, child.position.y],
				"respawns": child.health.respawn_count,
			}
	var state := {
		"id": str(_id),
		"origin": [_origin.x, _origin.y] if _origin != Vector2.INF else null,
		"picked": _picked,
		"respawned_at": [_respawned_at.x, _respawned_at.y] if _respawned_at != Vector2.INF else null,
		"deaths": _deaths,
		"errors": _errors.snapshot(),
		"players": players,
	}
	var tmp := _out + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(state))
	f.close()
	DirAccess.rename_absolute(tmp, _out)
