extends SceneTree
## One peer of a wall and city sync session (#498).
## Host: --host --save --port --out --mode. Client: --port --out --mode [--shot].


var _errors := _ErrorLog.new()
var _refused_wood := -1
var _place_error := ""
var _shot := false
var _gap := Vector2i(1 << 20, 0)


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
		printerr("wall_sync_probe: needs --port, --out, --save with --host, and the main scene")
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
			printerr("wall_sync_probe: could not host %s: %s" % [save, error])
			quit(1)
			return
		main.add_player(1)
		_park_mobs(main)
	else:
		main.add_player_joined(port)
	var world = main.get_node("World/worldMap")
	var phase := "idle"
	var opened := false
	var deadline := Time.get_ticks_msec() + 90000
	var next_write := 0
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(out + ".stop"):
		var me: Node2D = main.get_node_or_null("World/" + str(main.multiplayer.get_unique_id()))
		var ready := main.world_params != null and me != null
		if not host and mode in ["wall", "city", "drive"] and phase == "idle" and ready:
			phase = "working"
			_place_error = await _do_place(main, world, me, mode)
			phase = "done"
		if host and mode == "city" and not opened and FileAccess.file_exists(out + ".open"):
			opened = true
			var bits := FileAccess.get_file_as_string(out + ".open").replace(",", " ").split(" ", false)
			if bits.size() >= 2:
				main.get_node("World/StructureRequests").host_erase_wall(Vector2i(int(bits[0]), int(bits[1])))
		if not host and mode == "drive" and phase == "done" and not _shot and _tower_in_cities(main, world):
			if shot != "" and DisplayServer.get_name() != "headless":
				await _frames(20)
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
	var inventory: Inventory = main.get_node("Inventory")
	var requests = main.get_node("World/StructureRequests")
	var interaction: Interaction = main.get_node("World/Interaction")
	if mode == "wall":
		return await _place_one_wall(world, me, inventory, requests, interaction)
	return await _place_city(world, me, inventory, requests, interaction)


func _place_one_wall(world, me: Node2D, inventory: Inventory, requests, interaction: Interaction) -> String:
	inventory.add(Inventory.WOOD, 4)
	var water: Vector2i = _find_water(world)
	if water.x == 1 << 20:
		return "no water cell"
	me.global_position = interaction.cell_center(water)
	await _wait(400)
	var before := inventory.count_of(Inventory.WOOD)
	var bad: Array[Vector2i] = [water]
	requests.place(BuildCosts.WALL_BLOCK, bad)
	await _wait(600)
	_refused_wood = inventory.count_of(Inventory.WOOD)
	if _refused_wood != before:
		return "refused request spent wood (%d -> %d)" % [before, _refused_wood]
	var spot: Vector2i = _castle_touch(world)
	if spot.x == 1 << 20:
		return "no clear cell touching the castle"
	me.global_position = interaction.cell_center(spot) + Vector2(0, 48)
	await _wait(500)
	var one: Array[Vector2i] = [spot]
	if not requests.place(BuildCosts.WALL_BLOCK, one):
		return "wall place was not sent"
	var until := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < until and not world.has_wall(spot):
		await process_frame
	if not world.has_wall(spot):
		return "wall was not applied"
	return ""


func _place_city(world, me: Node2D, inventory: Inventory, requests, interaction: Interaction) -> String:
	inventory.add(Inventory.WOOD, 50)
	var spot: Dictionary = _ring_spot(world)
	if spot.is_empty():
		return "no 5x5 clear ring"
	var anchor: Vector2i = spot["anchor"]
	_gap = spot["gap"]
	me.global_position = interaction.cell_center(anchor) + Vector2(0, 48)
	await _wait(400)
	var tower_cell: Array[Vector2i] = [anchor]
	if not requests.place(BuildCosts.TOWER, tower_cell):
		return "tower place was not sent"
	var until := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < until and _tower_id(world) < 0:
		await process_frame
	if _tower_id(world) < 0:
		return "tower was not applied"
	var flag: Vector2i = _tower_flag(world)
	me.global_position = interaction.cell_center(flag)
	await _wait(300)
	for side in spot["sides"]:
		var run: Array[Vector2i] = side
		if not requests.place(BuildCosts.WALL_BLOCK, run):
			return "wall side was not sent"
		await _wait(200)
	until = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < until and not _ring_applied(world, spot["ring"]):
		await process_frame
	if not _ring_applied(world, spot["ring"]):
		return "ring was not applied"
	return ""


func _park_mobs(main) -> void:
	for node in main.get_node("World/Mobs").get_children():
		if node is Mob:
			node.global_position = Vector2(100000, 100000)


func _find_water(world) -> Vector2i:
	var spawn: Vector2i = world.resolve_player_spawn()
	for r in range(0, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cell := spawn + Vector2i(dx, dy)
				if world.predict_cell(cell)[0] == TileCatalog.WATER and not world.has_bridge(cell):
					return cell
	return Vector2i(1 << 20, 0)


func _castle_touch(world) -> Vector2i:
	var anchor := Vector2i.ZERO
	var found := false
	var placed: Dictionary = world.placed_structures()
	for id in placed:
		if str(placed[id]["name"]) == "castle":
			anchor = placed[id]["anchor"]
			found = true
			break
	if not found:
		return Vector2i(1 << 20, 0)
	var placer := ConstructionPlacer.new(world)
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var cell := anchor + Vector2i(dx, dy)
			if world.has_wall(cell) or world._structures.has_cell(cell):
				continue
			if world.get_cell_source_id(0, cell) == -1 or not world.predicted_clear(cell):
				continue
			var one: Array[Vector2i] = [cell]
			if placer.can_place_geometry(BuildCosts.WALL_BLOCK, one).is_empty():
				return cell
	return Vector2i(1 << 20, 0)


func _ring_spot(world) -> Dictionary:
	var structure := StructurePlacer.load_named("tower_wood")
	if structure == null:
		return {}
	var spawn: Vector2i = world.resolve_player_spawn()
	for radius in range(3, 48):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var cell := spawn + Vector2i(dx, dy)
				var found := _ring_at(world, structure, cell)
				if not found.is_empty():
					return found
	return {}


func _ring_at(world, structure: Structure, cell: Vector2i) -> Dictionary:
	if not _rect_clear(world, cell, 5):
		return {}
	var anchor: Vector2i = cell + Vector2i(2, 3)
	var one: Array[Vector2i] = [anchor]
	if not ConstructionPlacer.new(world).can_place_geometry(BuildCosts.TOWER, one).is_empty():
		return {}
	var ring := _perimeter(cell, cell + Vector2i(4, 4))
	var foot: Dictionary = StructurePlacer.footprint(structure, anchor)
	for r in ring:
		if foot.has(r) or not world.predicted_clear(r):
			return {}
	return {
		"anchor": anchor,
		"gap": cell + Vector2i(2, 0),
		"ring": ring,
		"sides": [
			_span(cell, true, 0, 0, 4),
			_span(cell, false, 4, 1, 3),
			_span(cell, true, 4, 0, 4),
			_span(cell, false, 0, 1, 3),
		],
	}


func _rect_clear(world, origin: Vector2i, size: int) -> bool:
	for y in size:
		for x in size:
			var c := origin + Vector2i(x, y)
			if not world.predicted_clear(c) or world.has_wall(c) or world._structures.has_cell(c):
				return false
	return true


func _perimeter(lo: Vector2i, hi: Vector2i) -> Array:
	var out: Array = []
	for x in range(lo.x, hi.x + 1):
		out.append(Vector2i(x, lo.y))
		out.append(Vector2i(x, hi.y))
	for y in range(lo.y + 1, hi.y):
		out.append(Vector2i(lo.x, y))
		out.append(Vector2i(hi.x, y))
	return out


func _span(origin: Vector2i, horizontal: bool, fixed: int, a: int, b: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in range(a, b + 1):
		out.append(origin + (Vector2i(i, fixed) if horizontal else Vector2i(fixed, i)))
	return out


func _ring_applied(world, ring: Array) -> bool:
	for cell in ring:
		if not world.has_wall(cell):
			return false
	return true


func _tower_id(world) -> int:
	var placed: Dictionary = world.placed_structures()
	for id in placed:
		if str(placed[id]["name"]) == "tower_wood":
			return int(id)
	return -1


func _tower_flag(world) -> Vector2i:
	var id := _tower_id(world)
	var towers: Dictionary = world._structures.towers()
	if towers.has(id) and not towers[id].is_empty():
		return towers[id][0]
	return Vector2i.ZERO


func _tower_in_cities(main, world) -> bool:
	var id := _tower_id(world)
	if id < 0:
		return false
	var cities = main.get_node("World/Cities")
	return cities.cities.has(id)


func _wait(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		await process_frame


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _write(out: String, main, world, me: Node2D) -> void:
	if out == "":
		return
	var walls: Array = []
	var autos: Array = []
	var cities: Array = []
	var tower := -1
	if main != null and main.world_params != null:
		tower = _tower_id(world)
		var cells: Array = world._walls._wall_cells.keys()
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.x < b.x or (a.x == b.x and a.y < b.y))
		for cell: Vector2i in cells:
			var caps: PackedStringArray = PackedStringArray(world._walls.cap_names(cell))
			walls.append([cell.x, cell.y, WallBuilder._atlas_wall_name(world._walls.piece(cell)), ",".join(caps)])
		var auto_cells: Array = world._structures.auto_cells().keys()
		auto_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.x < b.x or (a.x == b.x and a.y < b.y))
		for cell: Vector2i in auto_cells:
			autos.append([cell.x, cell.y, WallBuilder._atlas_wall_name(world._structures.object_at(cell))])
		var node = main.get_node("World/Cities")
		var ids: Array = node.cities.keys()
		ids.sort()
		for id in ids:
			cities.append([int(id), node.cities[id]["walls"].size(), node.cities[id]["interior"].size()])
	var inventory: Inventory = main.get_node("Inventory") if main != null else null
	var file := FileAccess.open(out + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"id": str(main.multiplayer.get_unique_id()) if main != null else "",
		"ready": main != null and main.world_params != null and me != null,
		"wood": inventory.count_of(Inventory.WOOD) if inventory != null else -1,
		"refused_wood": _refused_wood,
		"place_error": _place_error,
		"shot": _shot,
		"tower_id": tower,
		"gap": [_gap.x, _gap.y],
		"walls": walls,
		"autos": autos,
		"cities": cities,
		"errors": _errors.snapshot(),
	}))
	file.close()
	DirAccess.rename_absolute(out + ".tmp", out)
