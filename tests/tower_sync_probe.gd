extends SceneTree
## One peer of a tower sync session (#497). Modes place, capture, watch, drive.
## Host: --host --save --port --out. Client: --port --out --mode [--shot].


var _errors := _ErrorLog.new()
var _refused_wood := -1
var _aside := false
var _shot := false
var _place_error := ""


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
	var shot := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--save="):
			save = arg.trim_prefix("--save=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--shot="):
			shot = arg.trim_prefix("--shot=")
		elif arg == "--host":
			host = true
	if port == 0 or out == "" or (host and save == "") or change_scene_to_file("res://flagoria_main.tscn") != OK:
		printerr("tower_sync_probe: needs --port, --out, --save with --host, and the main scene")
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
			printerr("tower_sync_probe: could not host %s: %s" % [save, error])
			quit(1)
			return
		main.add_player(1)
		if mode == "place" or mode == "capture":
			main.get_node("World/TowerCapture").set_physics_process(false)
			# Place mode awards flags once. Discovery must not add points on top.
			main.get_node("FlagsHeldPoints").set_physics_process(false)
			main.get_node("Discovery").set_physics_process(false)
			for node in main.get_node("World/Mobs").get_children():
				if node is Mob:
					node.global_position = Vector2(100000, 100000)
	else:
		main.add_player_joined(port)
	var world = main.get_node("World/worldMap")
	var phase := "idle"
	var flags_ticked := false
	var capture_done := false
	var capture_more_done := false
	var deadline := Time.get_ticks_msec() + 90000
	var next_write := 0
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(out + ".stop"):
		var me: Node2D = main.get_node_or_null("World/" + str(main.multiplayer.get_unique_id()))
		var ready := main.world_params != null and me != null
		if not host and mode in ["place", "capture", "drive"] and phase == "idle" and ready:
			phase = "working"
			_place_error = await _do_place(main, world, me, mode)
			if mode != "place":
				_aside = _place_error == ""
			phase = "done"
		if host and mode == "place" and not flags_ticked and ready and _remote_tower(world):
			flags_ticked = true
			main.get_node("FlagsHeldPoints").tick()
		if host and mode == "capture" and ready:
			if not capture_done and FileAccess.file_exists(out + ".capture"):
				capture_done = true
				_scripted_ticks(main, world, FileAccess.get_file_as_string(out + ".capture"))
			if capture_done and not capture_more_done and FileAccess.file_exists(out + ".capture_more"):
				capture_more_done = true
				_scripted_ticks(main, world, FileAccess.get_file_as_string(out + ".capture_more"))
		if not host and mode == "drive" and phase == "done" and not _shot and _tower_owner(world) == 1:
			if shot != "" and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				_shot = root.get_texture().get_image().save_png(shot) == OK
			else:
				_shot = true
		if Time.get_ticks_msec() >= next_write:
			_write(out, main, world, me)
			next_write = Time.get_ticks_msec() + 100
		await process_frame
	_write(out, main, world, main.get_node_or_null("World/" + str(main.multiplayer.get_unique_id())))
	quit(0)


func _do_place(main, world, me: Node2D, mode: String) -> String:
	var interaction: Interaction = main.get_node("World/Interaction")
	var requests = main.get_node("World/StructureRequests")
	var inventory: Inventory = main.get_node("Inventory")
	var min_px := 180.0 if mode != "place" else 0.0
	var land: Variant = _search(world, func(cell: Vector2i) -> bool:
		return _tower_ok(world, cell, min_px))
	if land == null:
		return "no clear tower anchor"
	inventory.add(Inventory.WOOD, 10)
	if mode == "place":
		var water: Variant = _search(world, func(cell: Vector2i) -> bool:
			return world.predict_cell(cell)[0] == TileCatalog.WATER and not world.has_bridge(cell))
		if water == null:
			return "no water cell"
		me.global_position = interaction.cell_center(water) + Vector2(0, 48)
		await _wait(500)
		var before := inventory.count_of(Inventory.WOOD)
		var bad: Array[Vector2i] = [water]
		requests.place(BuildCosts.TOWER, bad)
		await _wait(700)
		_refused_wood = inventory.count_of(Inventory.WOOD)
		if _refused_wood != before:
			return "refused request spent wood (%d -> %d)" % [before, _refused_wood]
	me.global_position = interaction.cell_center(land) + Vector2(0, 48)
	await _wait(800)
	var one: Array[Vector2i] = [land]
	if not requests.place(BuildCosts.TOWER, one):
		return "place was not sent"
	var until := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < until and _tower_owner(world) <= 0:
		await process_frame
	if _tower_owner(world) <= 0:
		return "tower was not applied"
	if mode != "place":
		var info := _tower_wood(world)
		me.global_position = interaction.cell_center(info["flag"]) + Vector2(48, 0)
		await _wait(300)
	return ""


func _scripted_ticks(main, world, text: String) -> void:
	var parts := text.replace(",", " ").strip_edges().split(" ", false)
	if parts.size() < 2:
		return
	var ticks := int(parts[0])
	var delta := float(parts[1])
	var info := _tower_wood(world)
	if info.is_empty():
		return
	for node in main.get_node("World/Mobs").get_children():
		if node is Mob:
			node.global_position = Vector2(100000, 100000)
	var me: Node2D = main.get_node_or_null("World/" + str(main.multiplayer.get_unique_id()))
	if me == null:
		return
	me.global_position = world.to_global(world.map_to_local(info["flag"]))
	var capture = main.get_node("World/TowerCapture")
	for _i in ticks:
		capture.tick(delta)

func _wait(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		await process_frame

func _search(world, pred: Callable) -> Variant:
	var spawn: Vector2i = world.resolve_player_spawn()
	for r in range(0, 48):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cell := spawn + Vector2i(dx, dy)
				if pred.call(cell):
					return cell
	return null

func _tower_ok(world, cell: Vector2i, min_px: float) -> bool:
	var one: Array[Vector2i] = [cell]
	if not ConstructionPlacer.new(world).can_place_geometry(BuildCosts.TOWER, one).is_empty():
		return false
	if min_px <= 0.0:
		return true
	var centre: Vector2 = world.to_global(world.map_to_local(cell))
	for node in world.get_parent().get_children():
		if node is CharacterBody2D and str(node.name).is_valid_int() \
				and node.global_position.distance_to(centre) < min_px:
			return false
		if node is Mob and node.global_position.distance_to(centre) < min_px:
			return false
	for node in world.get_node("../Mobs").get_children():
		if node is Mob and node.global_position.distance_to(centre) < min_px:
			return false
	return true


func _tower_wood(world) -> Dictionary:
	var placed: Dictionary = world.placed_structures()
	var towers: Dictionary = world._structures.towers()
	for id in placed.keys():
		if str(placed[id]["name"]) == "tower_wood" and towers.has(id):
			return {"id": int(id), "flag": towers[id][0], "owner": int(placed[id]["owner"])}
	return {}


func _tower_owner(world) -> int:
	var info := _tower_wood(world)
	return int(info["owner"]) if not info.is_empty() else -1


func _remote_tower(world) -> bool:
	var owner := _tower_owner(world)
	return owner > 1


func _write(out: String, main, world, me: Node2D) -> void:
	if out == "":
		return
	var placements := []
	var capture := []
	var points := {}
	if main != null and main.world_params != null:
		var placed: Dictionary = world.placed_structures()
		var ids := placed.keys()
		ids.sort()
		for id in ids:
			var anchor: Vector2i = placed[id]["anchor"]
			placements.append([int(id), placed[id]["name"], int(placed[id]["owner"]), anchor.x, anchor.y])
		for entry in main.get_node("World/TowerCapture").capture_snapshot():
			capture.append([int(entry[0]), int(entry[1]), int(entry[2]), float(entry[3])])
		var scores: Points = main.get_node("Points")
		var score_ids := {1: true}
		var uid := int(main.multiplayer.get_unique_id())
		if uid > 0:
			score_ids[uid] = true
		for node in main.get_node("World").get_children():
			if str(node.name).is_valid_int():
				score_ids[int(str(node.name))] = true
		for row in placements:
			score_ids[int(row[2])] = true
		for peer_id in score_ids:
			points[str(peer_id)] = scores.total_of(int(peer_id))
	var inventory: Inventory = main.get_node("Inventory") if main != null else null
	var file := FileAccess.open(out + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"id": str(main.multiplayer.get_unique_id()) if main != null else "",
		"ready": main != null and main.world_params != null and me != null,
		"wood": inventory.count_of(Inventory.WOOD) if inventory != null else -1,
		"refused_wood": _refused_wood,
		"aside": _aside,
		"shot": _shot,
		"place_error": _place_error,
		"placements": placements,
		"capture": capture,
		"points": points,
		"errors": _errors.snapshot(),
	}))
	file.close()
	DirAccess.rename_absolute(out + ".tmp", out)
