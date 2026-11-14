extends SceneTree
## One peer of a castle sync session (#278).
## Host: --host --save --port --out. Client: --port --out --mode [--shot].
## Modes: play (the first joiner), watch (a late joiner), drive (screenshot).


var _errors := _ErrorLog.new()
var _shot := false


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
		printerr("castle_sync_probe: needs --port, --out, --save with --host, and the main scene")
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
			printerr("castle_sync_probe: could not host %s: %s" % [save, error])
			quit(1)
			return
		main.add_player(1)
		main.get_node("World/TowerCapture").set_physics_process(false)
		for node in main.get_node("World/Mobs").get_children():
			if node is Mob:
				node.global_position = Vector2(100000, 100000)
	else:
		main.add_player_joined(port)
	var world = main.get_node("World/worldMap")
	var framed := false
	var deadline := Time.get_ticks_msec() + 90000
	var next_write := 0
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(out + ".stop"):
		if main.multiplayer == null:
			break
		var me: Node2D = main.get_node_or_null("World/" + str(main.multiplayer.get_unique_id()))
		var ready := main.world_params != null and me != null
		if not host and mode == "drive" and ready and not framed and _castle_count(world) >= 2:
			framed = true
			me.global_position = _viewpoint(world)
			## The host drive shows an 854×480 phone window. A second process
			## started with --script keeps a smaller stretch rect unless the
			## window is resized twice after the scale mode is set.
			var win := main.get_window()
			win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
			win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
			win.content_scale_size = Vector2i(480, 270)
			win.size = Vector2i(480, 270)
			await _frames(2)
			win.size = Vector2i(854, 480)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_position(Vector2i(0, 0))
			DisplayServer.window_set_size(Vector2i(854, 480))
			await _frames(15)
			if shot != "" and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				var image := _without_clear_margin(win.get_texture().get_image())
				_shot = image.save_png(shot) == OK
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


func _castle_count(world) -> int:
	var n := 0
	for entry in world.placed_structures().values():
		if str(entry["name"]) == "castle":
			n += 1
	return n


func _viewpoint(world) -> Vector2:
	## South of the castles, so both courtyards sit in the phone view.
	var sum := Vector2.ZERO
	var n := 0
	for entry in world.placed_structures().values():
		if str(entry["name"]) != "castle":
			continue
		var anchor: Vector2i = entry["anchor"]
		sum += Vector2(anchor)
		n += 1
	if n == 0:
		return Vector2.ZERO
	var mid := Vector2i(roundi(sum.x / n), roundi(sum.y / n))
	return world.to_global(world.map_to_local(mid + Vector2i(0, 2)))


func _without_clear_margin(image: Image) -> Image:
	## A second window can leave the default clear color beside the stretch rect.
	var w := image.get_width()
	var h := image.get_height()
	if w < 2 or h < 2:
		return image
	var corner := image.get_pixel(0, 0)
	if corner.r > 0.35 or absf(corner.r - corner.g) > 0.02 or absf(corner.g - corner.b) > 0.02:
		return image
	var min_x := 0
	var max_x := w - 1
	var min_y := 0
	var max_y := h - 1
	while min_x < max_x and _column_is(image, min_x, corner):
		min_x += 1
	while max_x > min_x and _column_is(image, max_x, corner):
		max_x -= 1
	while min_y < max_y and _row_is(image, min_y, min_x, max_x, corner):
		min_y += 1
	while max_y > min_y and _row_is(image, max_y, min_x, max_x, corner):
		max_y -= 1
	if min_x == 0 and min_y == 0 and max_x == w - 1 and max_y == h - 1:
		return image
	return image.get_region(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))


func _column_is(image: Image, x: int, color: Color) -> bool:
	for y in image.get_height():
		if image.get_pixel(x, y).is_equal_approx(color) == false:
			return false
	return true


func _row_is(image: Image, y: int, min_x: int, max_x: int, color: Color) -> bool:
	for x in range(min_x, max_x + 1):
		if image.get_pixel(x, y).is_equal_approx(color) == false:
			return false
	return true


func _frames(count: int) -> void:
	for _i in count:
		await process_frame


func _write(out: String, main, world, me: Node2D) -> void:
	if out == "":
		return
	var castles := []
	if main != null and main.world_params != null:
		var placed: Dictionary = world.placed_structures()
		var ids := placed.keys()
		ids.sort()
		var towers: Dictionary = world._structures.towers()
		var castle := StartCastle.structure()
		for id in ids:
			if str(placed[id]["name"]) != "castle":
				continue
			var anchor: Vector2i = placed[id]["anchor"]
			var flag := Vector2i.ZERO
			if towers.has(id) and not towers[id].is_empty():
				flag = towers[id][0]
			var blocks := 0
			var cells: PackedStringArray = []
			for cell: Vector2i in StructurePlacer.footprint(castle, anchor):
				var clear: bool = world.is_clear_ground(cell)
				if not clear:
					blocks += 1
				var drawn: Vector2i = world.get_cell_atlas_coords(1, cell)
				var predicted: Array = world.predict_cell(cell)
				cells.append("%d,%d,%d,%d,%d,%d,%d" % [cell.x, cell.y, drawn.x, drawn.y,
						predicted[1].x, predicted[1].y, 0 if clear else 1])
			cells.sort()
			if flag != Vector2i.ZERO:
				world.is_clear_ground(flag)
			var flag_atlas: Vector2i = world.get_cell_atlas_coords(1, flag)
			castles.append({
				"owner": int(placed[id]["owner"]),
				"x": anchor.x,
				"y": anchor.y,
				"flag": [flag_atlas.x, flag_atlas.y],
				"blocks": blocks,
				"cells": "|".join(cells),
			})
	var file := FileAccess.open(out + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"id": _peer_id(main),
		"ready": main != null and main.world_params != null and me != null,
		"castles": castles,
		"shot": _shot,
		"errors": _errors.snapshot(),
	}))
	file.close()
	DirAccess.rename_absolute(out + ".tmp", out)
