extends SceneTree
## One peer of a cut sync session, run as its own headless process by
## test_cut_save_late_join (tests/saves/test_cut_save.gd) and
## test_cut_sync_two_players (tests/net/test_cut_sync.gd).
##   -- --port=N --out=PATH --host --save=SAVE  load SAVE and host it with a player
##   -- --port=N --out=PATH                     join localhost:N through the Join path
## Optional --cells=x,y;x,y lists cells to report besides the cut ones.
## Every 100 ms it writes PATH (JSON): its peer id, whether it has the map
## and its own player, its cut list, its wood and, for each cut or listed
## cell, what is drawn there and whether it blocks. While PATH.cut holds
## cells (x,y;x,y), it cuts each once through the normal cut path: its
## player steps next to the cell, then Interaction._cut runs. Engine errors
## it logged are in "errors". Stops when PATH.stop exists, or after 90 s.

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


static func parse_cells(text: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for part in text.strip_edges().split(";", false):
		var cell = WorldSave.parse_cell(part.strip_edges())
		if cell != null:
			out.append(cell)
	return out


func _run() -> void:
	var port := 0
	var save := ""
	var out := ""
	var host := false
	var listed: Array[Vector2i] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--save="):
			save = arg.trim_prefix("--save=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--cells="):
			listed = parse_cells(arg.trim_prefix("--cells="))
		elif arg == "--host":
			host = true
	if port == 0 or out == "" or (host and save == "") or change_scene_to_file("res://flagoria_main.tscn") != OK:
		printerr("cut_sync_probe: needs --port=N, --out=PATH, --save=PATH with --host, and the main scene")
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
			printerr("cut_sync_probe: could not host %s: %s" % [save, error])
			quit(1)
			return
		main.add_player(1)
	else:
		main.add_player_joined(port)
	var world = main.get_node("World/worldMap")
	var interaction: Interaction = main.get_node("World/Interaction")
	var done := {}
	var deadline := Time.get_ticks_msec() + 90000
	var next_write := 0
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(out + ".stop"):
		var me: Node2D = main.get_node_or_null("World/" + str(main.multiplayer.get_unique_id()))
		if me and main.world_params != null and FileAccess.file_exists(out + ".cut"):
			for cell in parse_cells(FileAccess.get_file_as_string(out + ".cut")):
				if done.has(cell):
					continue
				me.global_position = interaction.cell_center(cell) + Vector2(12, 0)
				var wait := Time.get_ticks_msec() + 300  # the host's copy of the player follows
				while Time.get_ticks_msec() < wait:
					await process_frame
				done[cell] = interaction._cut(cell)
		if Time.get_ticks_msec() >= next_write:
			next_write = Time.get_ticks_msec() + 100
			_write(out, main, world, listed, me != null)
		await process_frame
	quit(0)


static func cell_state(world, cell: Vector2i) -> Dictionary:
	## What a player meets on `cell`: the foliage tile, the decor under it
	## (a stump) and whether the cell is clear to walk. Draws its chunk first.
	var clear: bool = world.is_clear_ground(cell)
	var decor: Vector2i = world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, cell)
	var plant: Vector2i = world.get_cell_atlas_coords(1, cell)
	return {"plant": [plant.x, plant.y], "decor": [decor.x, decor.y], "clear": clear}


func _write(out: String, main, world, listed: Array[Vector2i], has_player: bool) -> void:
	var cuts: Dictionary = world.cut_changes()
	var cells := {}
	if main.world_params != null:
		for cell in listed:
			cells[WorldSave.cell_key(cell)] = cell_state(world, cell)
		for chunk in cuts:
			for key in cuts[chunk]:
				cells[key] = cell_state(world, WorldSave.parse_cell(key))
	var inventory: Inventory = main.get_node("Inventory")
	var file := FileAccess.open(out + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"id": str(main.multiplayer.get_unique_id()),
		"ready": main.world_params != null and has_player,
		"cuts": cuts,
		"cells": cells,
		"wood": inventory.count_of(Inventory.WOOD),
		"errors": _errors.snapshot(),
	}))
	file.close()
	DirAccess.rename_absolute(out + ".tmp", out)
