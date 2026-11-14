extends SceneTree
## One peer of a wall and city sync session (#498).
## Host: --host --save --port --out --mode. Client: --port --out --mode [--shot].


var _errors := _ErrorLog.new()
var _refused_wood := -1
var _place_error := ""
var _shot := false
var _gap := Vector2i(1 << 20, 0)
var _out := ""
## Cell the host erased after the open request. The sentinel means it has not.
var _erased := Vector2i(1 << 20, 0)


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
	_out = out
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
		if main.multiplayer == null:
			break
		var me: Node2D = main.get_node_or_null("World/" + str(main.multiplayer.get_unique_id()))
		var ready := main.world_params != null and me != null
		if not host and mode in ["wall", "city", "drive"] and phase == "idle" and ready:
			phase = "working"
			_place_error = await _do_place(main, world, me, mode)
			phase = "done"
		# The open file appears only once it has both coordinates (atomic rename).
		# An empty file is ignored: latching on create-before-write missed the
		# erase and the test then sat on its 15 s bound (one run, 22.9 s).
		if host and mode == "city" and not opened and FileAccess.file_exists(out + ".open"):
			var text := FileAccess.get_file_as_string(out + ".open").strip_edges()
			var bits := text.replace(",", " ").split(" ", false)
			if bits.size() >= 2 and bits[0].is_valid_int() and bits[1].is_valid_int():
				opened = true
				var cell := Vector2i(int(bits[0]), int(bits[1]))
				if not main.get_node("World/StructureRequests").host_erase_wall(cell):
					_place_error = "could not erase %s" % cell
				else:
					_erased = cell
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
	var fin: Node2D = null
	if main.multiplayer != null:
		fin = main.get_node_or_null("World/" + str(main.multiplayer.get_unique_id()))
	_write(out, main, world, fin)
	quit(0)


func _peer_id(main) -> String:
	if main == null or main.multiplayer == null:
		return ""
	return str(main.multiplayer.get_unique_id())


func _do_place(main, world, me: Node2D, mode: String) -> String:
	var inventory: Inventory = main.get_node("Inventory")
	var requests = main.get_node("World/StructureRequests")
	var interaction: Interaction = main.get_node("World/Interaction")
	if mode == "wall":
		return await _place_one_wall(world, me, inventory, requests, interaction)
	return await _place_city(main, world, me, inventory, requests, interaction, mode)


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


func _place_city(main, world, me: Node2D, inventory: Inventory, requests, interaction: Interaction, mode: String) -> String:
	## Map seed is fixed by the test (seed 11). Each place waits until the host
	## has this body, then until that place is on the map. No wall-clock sleep:
	## a short sleep raced the position sync and a rejected place then burned
	## the 8 s apply bound.
	inventory.add(Inventory.WOOD, 50)
	var spot: Dictionary = _ring_spot(world)
	if spot.is_empty():
		return "no 5x5 clear ring"
	var anchor: Vector2i = spot["anchor"]
	_gap = spot["gap"]
	var err := await _ready_to_build(main, me, interaction.cell_center(anchor) + Vector2(0, 48), mode)
	if err != "":
		return err
	var tower_cell: Array[Vector2i] = [anchor]
	if not requests.place(BuildCosts.TOWER, tower_cell):
		return "tower place was not sent"
	if not await _until(func() -> bool: return _tower_id(world) >= 0, 8000):
		return "tower was not applied"
	var flag: Vector2i = _tower_flag(world)
	err = await _ready_to_build(main, me, interaction.cell_center(flag), mode)
	if err != "":
		return err
	for side in spot["sides"]:
		var run: Array[Vector2i] = side
		if not requests.place(BuildCosts.WALL_BLOCK, run):
			return "wall side was not sent"
		if not await _until(func() -> bool: return _cells_walled(world, run), 8000):
			return "wall side was not applied"
	if not _ring_applied(world, spot["ring"]):
		return "ring was not applied"
	return ""


func _ready_to_build(main, me: Node2D, where: Vector2, mode: String) -> String:
	## Stress peers publish positions in the host probe's status file. The live
	## drive hosts from the game itself, which does not write that file.
	if mode == "drive":
		await _drive_settle(me, where, 400)
		return ""
	return await _wait_host_position(main, me, where, 5000)


func _drive_settle(me: Node2D, where: Vector2, ms: int) -> void:
	## Bounded settle for the screenshot drive only. Stress mode does not call this.
	_pin(me, where)
	await _wait(ms)


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


func _cells_walled(world, cells: Array) -> bool:
	for cell in cells:
		if not world.has_wall(cell):
			return false
	return true


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
		"shot": _shot,
		"tower_id": tower,
		"gap": [_gap.x, _gap.y],
		"erased": [_erased.x, _erased.y],
		"peers": peers,
		"walls": walls,
		"autos": autos,
		"cities": cities,
		"errors": _errors.snapshot(),
	}))
	file.close()
	DirAccess.rename_absolute(out + ".tmp", out)
