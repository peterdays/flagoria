extends SceneTree
## One peer of a cut sync session, run as its own headless process by
## test_cut_save_late_join (tests/saves/test_cut_save.gd) and
## test_cut_sync_two_players (tests/net/test_cut_sync.gd) and
## test_regrow_sync_two_players (tests/net/test_regrow_sync.gd) and
## test_structure_sync_join and test_castle_sync_join (tests/net/test_structure_sync.gd)
## and test_dead_cut_client and test_cut_refused_two_players (tests/net/test_cut_sync.gd) and
## test_sprout_sync_two_players (tests/net/test_sprout_sync.gd).
##   -- --port=N --out=PATH --host --save=SAVE  load SAVE and host it with a player
##   -- --port=N --out=PATH                     join localhost:N through the Join path
## Optional --cells=x,y;x,y lists cells to report besides the cut ones.
## Optional --regrow=S sets this peer's map-wide regrow delay (seconds); its
## player then steps 64 px away from its cuts 500 ms after the last one, so
## it does not hold a stump back. The time (unix ms) each cut cell left the
## cut list is in "regrown". While PATH.forge exists, a client sends the
## host one apply_regrow_cells listing every listed cell, once, as a peer
## that tries to regrow by itself would.
## Optional --place=NAME@x,y (host): place res://structures/NAME.txt with its
## anchor on x,y while the host is still alone, before its own player. While
## PATH.forge_place exists, a client sends every other client a forged
## receive_map_params carrying one placement, once.
## While PATH.regrow holds S, this peer's map-wide regrow delay is S.
## While PATH.kill holds a peer id (host), it sets that peer's player's health
## to 0 once, with a 600 s respawn delay. While PATH.dead_cut holds cells, once
## its own player is dead it steps next to each cell, waits 300 ms, drags a
## selection over it with screen touch events in interact mode, then sends the
## host request_cut for it directly, as a peer that skips its own check would;
## "dead_cut" then counts the cells the drag covered in reach.
## While PATH.swing exists (client), it chops two trees through start_chop:
## one far from where the host still sees it (position sync paused), which the
## host refuses, then one near its spawn after sync is on again, which the
## host accepts. "refused_fells" / "refused_sounds" are the fall count and
## sound names after the refused chop; "fells" and "sounds" are after both.
## Every 100 ms it writes PATH (JSON): its peer id, whether it has the map
## and its own player, its cut list, its wood and, for each cut or listed
## cell, what is drawn there and whether it blocks, and the cell each
## player (by peer id) stands on. While PATH.cut holds
## cells (x,y;x,y), it cuts each once through the normal cut path: its
## player steps next to the cell, then Interaction._cut runs. Engine errors
## it logged are in "errors". Stops when PATH.stop exists, or after 90 s.

var _errors := _ErrorLog.new()
var _swing_started := false
var _swing_done := false
var _swing_error := ""
var _far_cell := Vector2i(-999999, -999999)
var _near_cell := Vector2i(-999999, -999999)
var _refused_fells := 0
var _refused_sounds: Array = []


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
	var killed := false
	var dead_cut := -1
	var deadline := Time.get_ticks_msec() + 90000
	var next_write := 0
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(out + ".stop"):
		# The peer API is null for a frame while a client connects. Calling
		# get_unique_id then is a script error, and the load job treats that
		# as a failed test even when the scenario later passes.
		if main.multiplayer == null:
			await process_frame
			continue
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
		if me and main.world_params != null and FileAccess.file_exists(out + ".plank"):
			var inventory: Inventory = main.get_node("Inventory")
			for cell in parse_cells(FileAccess.get_file_as_string(out + ".plank")):
				if done.has(cell):
					continue
				me.global_position = interaction.cell_center(cell) + Vector2(12, 0)
				inventory.add(Inventory.WOOD, 1)
				var wait := Time.get_ticks_msec() + 300
				while Time.get_ticks_msec() < wait:
					await process_frame
				var one: Array[Vector2i] = [cell]
				done[cell] = interaction.place_planks(one)
		if not moved_away and me:
			var wait := Time.get_ticks_msec() + 500  # the host has decided the cuts
			while Time.get_ticks_msec() < wait:
				await process_frame
			me.global_position += Vector2(0, 64)
			moved_away = true
		if FileAccess.file_exists(out + ".regrow"):
			world.regrow_delay = FileAccess.get_file_as_string(out + ".regrow").to_float()
		if not killed and host and FileAccess.file_exists(out + ".kill"):
			var victim: Node2D = main.get_node_or_null("World/" + FileAccess.get_file_as_string(out + ".kill").strip_edges())
			if victim:
				killed = true
				victim.health.respawn_delay = 600.0
				victim.health.set_health_now(0)
		if dead_cut < 0 and me and me.health.is_dead() and FileAccess.file_exists(out + ".dead_cut"):
			dead_cut = 0
			interaction.set_mode(Interaction.Mode.INTERACT)
			for cell in parse_cells(FileAccess.get_file_as_string(out + ".dead_cut")):
				var centre := interaction.cell_center(cell)
				me.global_position = centre + Vector2(12, 0)
				var wait := Time.get_ticks_msec() + 300  # the host's copy of the player follows
				while Time.get_ticks_msec() < wait:
					await process_frame
				dead_cut += interaction.choppables_in_rect(Rect2(centre - Vector2(10, 10), Vector2(20, 20))).size()
				var to_view := interaction.get_canvas_transform()
				var button: Node = main.get_node("CanvasLayer1/TouchScreenButton")
				var origin: Vector2 = button.aim_center()
				var delta: Vector2 = (to_view * centre) - (to_view * me.global_position)
				var press := InputEventScreenTouch.new()
				press.position = origin
				press.pressed = true
				root.push_input(press, true)
				var drag := InputEventScreenDrag.new()
				drag.position = origin + delta
				root.push_input(drag, true)
				var lift := InputEventScreenTouch.new()
				lift.position = drag.position
				root.push_input(lift, true)
				interaction.request_cut.rpc_id(1, cell)
		if not host and not _swing_started and me and main.world_params != null \
				and FileAccess.file_exists(out + ".swing"):
			_swing_started = true
			await _swing(me, world, interaction)
		if not forged and not host and FileAccess.file_exists(out + ".forge"):
			forged = true
			interaction.apply_regrow_cells.rpc_id(1, listed)
		if not forged_place and not host and FileAccess.file_exists(out + ".forge_place"):
			forged_place = true
			for peer in main.multiplayer.get_peers():
				if peer != 1:
					main.rpc_id(peer, "receive_map_params", main.world_params.to_dict(), Vector2.INF,
							world.cut_changes(), [["guard_post", main.multiplayer.get_unique_id(), Vector2i(3, 3)]], [])
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
			_write(out, main, world, listed, me, regrown, dead_cut)
		await process_frame
	quit(0)


func _swing(me: Node2D, world, interaction: Interaction) -> void:
	## A far chop the host refuses, then a near one it accepts (#350).
	interaction.bind(me)
	interaction.set_mode(Interaction.Mode.INTERACT)
	var picked := _pick_trees(world, interaction, me.global_position)
	if picked["error"] != "":
		_swing_error = picked["error"]
		_swing_done = true
		return
	_far_cell = picked["far"]
	_near_cell = picked["near"]
	var sync: MultiplayerSynchronizer = me.get_node("MultiplayerSynchronizer")
	# process_mode does not stop this node: the replicator polls it itself.
	# A long interval keeps the host on the spawn position for the far chop.
	sync.replication_interval = 30.0
	var hold := Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < hold:
		await process_frame
	var far_ok: bool = await _swing_at(me, world, interaction, _far_cell, false)
	_refused_fells = interaction._chop.fell_count
	_refused_sounds = _sound_names(interaction)
	sync.replication_interval = 0.0
	var near_ok: bool = await _swing_at(me, world, interaction, _near_cell, true)
	if not far_ok or not near_ok:
		_swing_error = "chop did not start (far %s, near %s, cells %s %s)" % [far_ok, near_ok, _far_cell, _near_cell]
	_swing_done = true


func _swing_at(me: Node2D, world, interaction: Interaction, cell: Vector2i, settle: bool) -> bool:
	## Stand next to `cell`, draw its chunk, and play one chop. When `settle`,
	## wait so the host's copy of this player arrives before the request.
	me.global_position = interaction.cell_center(cell) + Vector2(12, 0)
	world.generate_chunk(me.position)
	if settle:
		var until := Time.get_ticks_msec() + 800
		while Time.get_ticks_msec() < until:
			await process_frame
	if world.choppable(cell) == null or not interaction.start_chop(cell):
		return false
	var until := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < until and interaction.chopping():
		await process_frame
	until = Time.get_ticks_msec() + 1000  # the host's answer
	while Time.get_ticks_msec() < until:
		await process_frame
	return true


func _pick_trees(world, interaction: Interaction, origin: Vector2) -> Dictionary:
	## A tree the host will call out of reach, and one inside its spawn chunk.
	var far_min := Interaction.CHOP_REACH + Interaction.REACH_SLACK + 128.0
	var near_max := 14.0 * 16.0
	var origin_cell: Vector2i = world.local_to_map(world.to_local(origin))
	var far := Vector2i(-999999, -999999)
	var near := Vector2i(-999999, -999999)
	var near_dist := INF
	for r in 80:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cell := origin_cell + Vector2i(dx, dy)
				var type := InteractableCatalog.type_at(world.predict_cell(cell)[1])
				if type == null or type.id != "tree":
					continue
				var dist := origin.distance_to(interaction.cell_center(cell))
				if far.x < -100000 and dist >= far_min:
					far = cell
				if dist <= near_max and dist < near_dist and cell != far:
					near = cell
					near_dist = dist
		if far.x > -100000 and near.x > -100000:
			break
	if far.x < -100000 or near.x < -100000:
		return {"error": "no far and near tree from %s (far %s, near %s)" % [origin, far, near]}
	return {"error": "", "far": far, "near": near}


static func _sound_names(interaction: Interaction) -> Array:
	var names := []
	for stream in interaction.sfx_log:
		names.append(stream.resource_path.get_file().get_basename() if stream != null else "")
	return names


static func cell_state(world, cell: Vector2i) -> Dictionary:
	## What a player meets on `cell`: the foliage tile, the decor under it
	## (a stump), whether it is clear to walk, and whether a plank bridge is
	## there. Draws its chunk first.
	var clear: bool = world.is_clear_ground(cell)
	var decor: Vector2i = world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, cell)
	var plant: Vector2i = world.get_cell_atlas_coords(1, cell)
	var predicted: Array = world.predict_cell(cell)
	return {"plant": [plant.x, plant.y], "decor": [decor.x, decor.y], "clear": clear,
		"bridge": world.has_bridge(cell),
		"predict": [predicted[0].x, predicted[0].y, predicted[1].x, predicted[1].y]}


func _write(out: String, main, world, listed: Array[Vector2i], me: Node2D, regrown: Dictionary, dead_cut: int) -> void:
	var cuts: Dictionary = world.cut_changes()
	var cells := {}
	if main.world_params != null:
		for cell in listed:
			cells[WorldSave.cell_key(cell)] = cell_state(world, cell)
		if _far_cell.x > -100000:
			cells[WorldSave.cell_key(_far_cell)] = cell_state(world, _far_cell)
		if _near_cell.x > -100000:
			cells[WorldSave.cell_key(_near_cell)] = cell_state(world, _near_cell)
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
	var players := {}
	for node in main.get_node("World").get_children():
		if node is CharacterBody2D and str(node.name).is_valid_int():
			var at: Vector2i = world.local_to_map(world.to_local(node.global_position))
			players[str(node.name)] = [at.x, at.y]
	var inventory: Inventory = main.get_node("Inventory")
	var interaction: Interaction = main.get_node("World/Interaction")
	var sounds := _sound_names(interaction)
	var bridges := []
	for entry in world.bridges_for_sync():
		bridges.append("%d,%d" % [entry[0], entry[1]])
	bridges.sort()
	var file := FileAccess.open(out + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"id": str(main.multiplayer.get_unique_id()),
		"ready": main.world_params != null and me != null,
		"dead": me != null and me.health.is_dead(),
		"dead_cut": dead_cut,
		"cuts": cuts,
		"cells": cells,
		"wood": inventory.count_of(Inventory.WOOD),
		"regrown": regrown,
		"placements": placements,
		"bridges": bridges,
		"players": players,
		"place_refused": refused,
		"errors": _errors.snapshot(),
		"sounds": sounds,
		"fells": interaction._chop.fell_count,
		"refused_fells": _refused_fells,
		"refused_sounds": _refused_sounds,
		"swing_done": _swing_done,
		"swing_error": _swing_error,
		"far": WorldSave.cell_key(_far_cell) if _far_cell.x > -100000 else "",
		"near": WorldSave.cell_key(_near_cell) if _near_cell.x > -100000 else "",
	}))
	file.close()
	DirAccess.rename_absolute(out + ".tmp", out)
