extends SceneTree
## One peer of a cut sync session, run as its own headless process by
## test_cut_save_late_join (tests/saves/test_cut_save.gd) and
## test_cut_sync_two_players (tests/net/test_cut_sync.gd) and
## test_regrow_sync_two_players (tests/net/test_regrow_sync.gd) and
## test_structure_sync_join (tests/net/test_structure_sync.gd).
##   -- --port=N --out=PATH --host --save=SAVE  load SAVE and host it with a player
##   -- --port=N --out=PATH                     join localhost:N through the Join path
## Optional --cells=x,y;x,y lists cells to report besides the cut ones.
## Optional --regrow=S sets this peer's map-wide regrow delay (seconds); its
## player then steps 64 px away from its cuts 500 ms after the last one, so
## it does not hold a stump back. The time (unix ms) each cut cell left the
## cut list is in "regrown". While PATH.forge exists, a client sends the
## host apply_regrow for each listed cell once, as a peer that tries to
## regrow by itself would.
## Optional --place=NAME@x,y (host): place res://structures/NAME.txt with its
## anchor on x,y while the host is still alone, before its own player. While
## PATH.forge_place exists, a client sends every other client a forged
## receive_map_params carrying one placement, once.
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
	var regrow := -1.0
	var place := ""
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
		elif arg.begins_with("--regrow="):
			regrow = arg.trim_prefix("--regrow=").to_float()
		elif arg.begins_with("--place="):
			place = arg.trim_prefix("--place=")
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
		if place != "":
			var cell = WorldSave.parse_cell(place.get_slice("@", 1))
			var structure := StructurePlacer.load_named(place.get_slice("@", 0))
			if cell == null or structure == null or main.get_node("World/worldMap").place_structure(structure, cell, 1) < 0:
				printerr("cut_sync_probe: could not place %s" % place)
				quit(1)
				return
		main.add_player(1)
	else:
		main.add_player_joined(port)
	var world = main.get_node("World/worldMap")
	var interaction: Interaction = main.get_node("World/Interaction")
	if regrow >= 0.0:
		world.regrow_delay = regrow
	var done := {}
	var seen_cut := {}
	var regrown := {}
	var forged := false
	var forged_place := false
	var moved_away := true
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
				moved_away = regrow < 0.0
		if not moved_away and me:
			var wait := Time.get_ticks_msec() + 500  # the host has decided the cuts
			while Time.get_ticks_msec() < wait:
				await process_frame
			me.global_position += Vector2(0, 64)
			moved_away = true
		if not forged and not host and FileAccess.file_exists(out + ".forge"):
			forged = true
			for cell in listed:
				interaction.apply_regrow.rpc_id(1, cell)
		if not forged_place and not host and FileAccess.file_exists(out + ".forge_place"):
			forged_place = true
			for peer in main.multiplayer.get_peers():
				if peer != 1:
					main.rpc_id(peer, "receive_map_params", main.world_params.to_dict(), Vector2.INF,
							world.cut_changes(), [["guard_post", main.multiplayer.get_unique_id(), Vector2i(3, 3)]])
		var now_cut: Dictionary = world.cut_changes()
		var keys := {}
		for chunk in now_cut:
			for key in now_cut[chunk]:
				keys[key] = true
				seen_cut[key] = true
		for key in seen_cut:
			if not keys.has(key) and not regrown.has(key):
				regrown[key] = int(Time.get_unix_time_from_system() * 1000.0)
		if Time.get_ticks_msec() >= next_write:
			next_write = Time.get_ticks_msec() + 100
			_write(out, main, world, listed, me != null, regrown)
		await process_frame
	quit(0)


static func cell_state(world, cell: Vector2i) -> Dictionary:
	## What a player meets on `cell`: the foliage tile, the decor under it
	## (a stump) and whether the cell is clear to walk. Draws its chunk first.
	var clear: bool = world.is_clear_ground(cell)
	var decor: Vector2i = world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, cell)
	var plant: Vector2i = world.get_cell_atlas_coords(1, cell)
	var predicted: Array = world.predict_cell(cell)
	return {"plant": [plant.x, plant.y], "decor": [decor.x, decor.y], "clear": clear,
		"predict": [predicted[0].x, predicted[0].y, predicted[1].x, predicted[1].y]}


func _write(out: String, main, world, listed: Array[Vector2i], has_player: bool, regrown: Dictionary) -> void:
	var cuts: Dictionary = world.cut_changes()
	var cells := {}
	if main.world_params != null:
		for cell in listed:
			cells[WorldSave.cell_key(cell)] = cell_state(world, cell)
		for chunk in cuts:
			for key in cuts[chunk]:
				cells[key] = cell_state(world, WorldSave.parse_cell(key))
	var placements := []
	var placed: Dictionary = world.placed_structures()
	var ids := placed.keys()
	ids.sort()
	for id in ids:
		var anchor: Vector2i = placed[id]["anchor"]
		placements.append([placed[id]["name"], placed[id]["owner"], anchor.x, anchor.y])
	var refused: Array = []
	var guard := StructurePlacer.load_named("guard_post")
	if guard != null and not listed.is_empty():
		refused = world.can_place_structure(guard, listed[0])
	var inventory: Inventory = main.get_node("Inventory")
	var file := FileAccess.open(out + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"id": str(main.multiplayer.get_unique_id()),
		"ready": main.world_params != null and has_player,
		"cuts": cuts,
		"cells": cells,
		"wood": inventory.count_of(Inventory.WOOD),
		"regrown": regrown,
		"placements": placements,
		"place_refused": refused,
		"errors": _errors.snapshot(),
	}))
	file.close()
	DirAccess.rename_absolute(out + ".tmp", out)
