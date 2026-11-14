extends SceneTree
## One peer of a buildable-castle sync session (#527). Modes place, watch.


var _errors := _ErrorLog.new()
var _refused_wood := -1
var _place_error := ""
var _out := ""


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
	var mode := "watch"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--save="):
			save = arg.trim_prefix("--save=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg == "--host":
			host = true
	_out = out
	if port == 0 or out == "" or (host and save == "") or change_scene_to_file("res://flagoria_main.tscn") != OK:
		printerr("castle_build_sync_probe: needs --port, --out, --save with --host, and the main scene")
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
			printerr("castle_build_sync_probe: could not host %s: %s" % [save, error])
			quit(1)
			return
		main.add_player(1)
	else:
		main.add_player_joined(port)
	var world = main.get_node("World/worldMap")
	var phase := "idle"
	var deadline := Time.get_ticks_msec() + 90000
	var next_write := 0
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(out + ".stop"):
		if main.multiplayer == null:
			break
		var me: Node2D = main.get_node_or_null("World/" + str(main.multiplayer.get_unique_id()))
		var ready := main.world_params != null and me != null
		if not host and mode == "place" and phase == "idle" and ready:
			phase = "working"
			_place_error = await _do_place(main, world, me)
			phase = "done"
		if Time.get_ticks_msec() >= next_write:
			_write(out, main, world, me)
			next_write = Time.get_ticks_msec() + 100
		await process_frame
	var fin: Node2D = null
	if main.multiplayer != null:
		fin = main.get_node_or_null("World/" + str(main.multiplayer.get_unique_id()))
	_write(out, main, world, fin)
	quit(0)


func _do_place(main, world, me: Node2D) -> String:
	var interaction: Interaction = main.get_node("World/Interaction")
	var requests = main.get_node("World/StructureRequests")
	var inventory: Inventory = main.get_node("Inventory")
	var land: Variant = _search(world, func(cell: Vector2i) -> bool:
		return _castle_ok(world, cell, 0))
	if land == null:
		return "no clear castle anchor"
	var water: Variant = _search(world, func(cell: Vector2i) -> bool:
		return world.predict_cell(cell)[0] == TileCatalog.WATER and not world.has_bridge(cell))
	if water == null:
		return "no water cell"
	var err := await _ready_to_build(main, me, interaction.cell_center(water) + Vector2(0, 48))
	if err != "":
		return err
	var before := inventory.count_of(Inventory.WOOD)
	inventory.add(Inventory.WOOD, 50)
	var bad: Array[Vector2i] = [water]
	requests.place(BuildCosts.CASTLE, bad, 0)
	if not await _until(func() -> bool: return inventory.count_of(Inventory.WOOD) == before + 50, 8000):
		return "refused request did not settle wood"
	_refused_wood = inventory.count_of(Inventory.WOOD)
	if _refused_wood != before + 50:
		return "refused request spent wood (%d -> %d)" % [before + 50, _refused_wood]
	err = await _ready_to_build(main, me, interaction.cell_center(land) + Vector2(0, 48))
	if err != "":
		return err
	var one: Array[Vector2i] = [land]
	if not requests.place(BuildCosts.CASTLE, one, 0):
		return "place was not sent"
	var builder: int = main.multiplayer.get_unique_id()
	var castles_before: int = _castle_count(world, builder)
	if not await _until(func() -> bool: return _castle_count(world, builder) > castles_before, 8000):
		return "built castle was not applied"
	return ""


func _ready_to_build(main, me: Node2D, where: Vector2) -> String:
	return await _wait_host_position(main, me, where, 5000)


func _wait_host_position(main, me: Node2D, where: Vector2, ms: int) -> String:
	var sync := me.get_node_or_null("MultiplayerSynchronizer")
	if sync is MultiplayerSynchronizer:
		(sync as MultiplayerSynchronizer).replication_interval = 0.0
	var peer_id := str(main.multiplayer.get_unique_id())
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		_pin(me, where)
		if _host_sees_position(peer_id, where, 4.0):
			return ""
		await process_frame
	return "host did not ack the player at %s" % where


func _pin(me: Node2D, where: Vector2) -> void:
	me.global_position = where
	if me is CharacterBody2D:
		(me as CharacterBody2D).velocity = Vector2.ZERO


func _host_sees_position(peer_id: String, where: Vector2, slack: float) -> bool:
	var path := _out.get_base_dir().path_join("p0.json")
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return false
	var pos = data.get("peers", {}).get(peer_id, null)
	if not pos is Array or pos.size() < 2:
		return false
	return Vector2(float(pos[0]), float(pos[1])).distance_to(where) <= slack


func _until(cond: Callable, ms: int) -> bool:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _castle_count(world, owner: int) -> int:
	var n := 0
	for p in world.placed_structures().values():
		if str(p["name"]) == "castle" and int(p["owner"]) == owner:
			n += 1
	return n


func _search(world, pred: Callable) -> Variant:
	var spawn: Vector2i = world.resolve_player_spawn()
	for r in range(0, 64):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cell := spawn + Vector2i(dx, dy)
				if pred.call(cell):
					return cell
	return null


func _castle_ok(world, cell: Vector2i, turns: int) -> bool:
	for p in world.placed_structures().values():
		if str(p["name"]) == "castle" and p["anchor"].distance_to(cell) < 14:
			return false
	var one: Array[Vector2i] = [cell]
	if not ConstructionPlacer.new(world).can_place_geometry(BuildCosts.CASTLE, one, turns).is_empty():
		return false
	return true


func _peer_id(main) -> String:
	if main == null or main.multiplayer == null:
		return ""
	return str(main.multiplayer.get_unique_id())


func _sync_rows(world) -> Array:
	var rows: Array = []
	for entry in world.structures_for_sync():
		rows.append(entry)
	rows.sort_custom(func(a: Array, b: Array) -> bool: return str(a) < str(b))
	return rows


func _write(out: String, main, world, me: Node2D) -> void:
	if out == "":
		return
	var inventory: Inventory = main.get_node("Inventory") if main != null else null
	var peers := {}
	var world_root: Node = null
	if main != null:
		world_root = main.get_node_or_null("World")
	if world_root != null:
		for child in world_root.get_children():
			if child is CharacterBody2D and str(child.name).is_valid_int():
				peers[str(child.name)] = [child.global_position.x, child.global_position.y]
	var file := FileAccess.open(out + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"id": _peer_id(main),
		"ready": main != null and main.world_params != null and me != null,
		"wood": inventory.count_of(Inventory.WOOD) if inventory != null else -1,
		"refused_wood": _refused_wood,
		"place_error": _place_error,
		"peers": peers,
		"sync": _sync_rows(world),
		"errors": _errors.snapshot(),
	}))
	file.close()
	DirAccess.rename_absolute(out + ".tmp", out)