extends SceneTree
## One peer of the dedicated cut-and-hit round (tests/net/test_dedicated_play_round.gd).
##
##   -- --port=N --out=PATH --cells=x,y [--mob=mob_N] [--rate=F] --dedicated --save=SAVE
##       dedicated server, no local player. --rate is the mob rate the plan used.
##   -- --port=N --out=PATH --cells=x,y [--mob=mob_N]
##       client. PATH.cut lists cells to cut through Interaction._cut.
##       PATH.hit asks this client to swing at --mob until it is gone.
##
## Writes a JSON snapshot about every 100 ms. Quits when PATH.stop exists.


var _errors := _ErrorLog.new()


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
	var out := ""
	var save := ""
	var dedicated := false
	var rate := -1.0
	var mob_name := ""
	var listed: Array[Vector2i] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--save="):
			save = arg.trim_prefix("--save=")
		elif arg.begins_with("--cells="):
			listed = _parse_cells(arg.trim_prefix("--cells="))
		elif arg.begins_with("--mob="):
			mob_name = arg.trim_prefix("--mob=")
		elif arg.begins_with("--rate="):
			rate = arg.trim_prefix("--rate=").to_float()
		elif arg == "--dedicated":
			dedicated = true
	if port == 0 or out == "" or (dedicated and save == "") or change_scene_to_file("res://flagoria_main.tscn") != OK:
		printerr("dedicated_play_probe: needs --port=N --out=PATH, and --save=PATH with --dedicated")
		quit(1)
		return
	await process_frame
	await process_frame
	var main = current_scene
	if dedicated:
		var loaded: Dictionary = MapSave.load_map(save)
		if rate >= 0.0:
			root.get_node("GameSettings").set_mob_rate(rate, false)
		if loaded["error"] != "" or main.start_dedicated_server(port, loaded["params"]) != OK:
			printerr("dedicated_play_probe: could not host %s: %s" % [save, loaded["error"]])
			quit(1)
			return
	else:
		main.add_player_joined(port)
	var world = main.get_node("World/worldMap")
	var interaction: Interaction = main.get_node("World/Interaction")
	var cut_done := {}
	var hitting := false
	var next_swing := 0
	var seen: Array[int] = []
	var watched_hp := -1
	var present := false
	var deadline := Time.get_ticks_msec() + 90000
	var next_write := 0
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(out + ".stop"):
		var me: Node2D = main.get_node_or_null("World/" + str(main.multiplayer.get_unique_id()))
		if not dedicated and me and main.world_params != null and FileAccess.file_exists(out + ".cut"):
			for cell in _parse_cells(FileAccess.get_file_as_string(out + ".cut")):
				if cut_done.has(cell):
					continue
				me.global_position = interaction.cell_center(cell) + Vector2(12, 0)
				var wait := Time.get_ticks_msec() + 300
				while Time.get_ticks_msec() < wait:
					await process_frame
				cut_done[cell] = interaction._cut(cell)
		var mob: Mob = null
		if mob_name != "":
			mob = main.get_node_or_null("World/Mobs/" + mob_name) as Mob
		if mob:
			present = true
			watched_hp = mob.hp
			if not seen.has(mob.state):
				seen.append(mob.state)
		elif present:
			present = false
		if not dedicated and me and FileAccess.file_exists(out + ".hit") and mob:
			hitting = true
			_sword_on(me, mob)
			if Time.get_ticks_msec() >= next_swing and not me.isAttacking:
				me.attack_animation.rpc()
				next_swing = Time.get_ticks_msec() + 600
		if Time.get_ticks_msec() >= next_write:
			next_write = Time.get_ticks_msec() + 100
			_write(out, main, world, listed, me, dedicated, mob_name, seen, watched_hp, present, hitting)
		await process_frame
	quit(0)


static func _parse_cells(text: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for part in text.strip_edges().split(";", false):
		var cell = WorldSave.parse_cell(part)
		if cell != null:
			cells.append(cell)
	return cells


static func _sword_on(player: Node2D, mob: Mob) -> void:
	var blade: Node2D = player.get_node("weapon/sword/CollisionShape2D")
	player.position += mob.hurt_box.global_position - blade.global_position
	player.velocity = Vector2.ZERO


func _write(out: String, main, world, listed: Array[Vector2i], me: Node2D, dedicated: bool,
		mob_name: String, seen: Array[int], watched_hp: int, present: bool, hitting: bool) -> void:
	var players: Array[String] = []
	for node in main.get_node("World").get_children():
		if node is CharacterBody2D and str(node.name).is_valid_int():
			players.append(str(node.name))
	players.sort()
	var cells := {}
	if main.world_params != null:
		for cell in listed:
			var decor: Vector2i = world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, cell)
			var plant: Vector2i = world.get_cell_atlas_coords(1, cell)
			cells[WorldSave.cell_key(cell)] = {
				"plant": [plant.x, plant.y],
				"decor": [decor.x, decor.y],
				"clear": world.is_clear_ground(cell),
			}
	var cuts: Array[String] = []
	var changed: Dictionary = world.cut_changes()
	for chunk in changed:
		for key in changed[chunk]:
			cuts.append(key)
	cuts.sort()
	var wood := 0
	if not dedicated:
		wood = main.get_node("Inventory").count_of(Inventory.WOOD)
	var file := FileAccess.open(out + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"id": str(main.multiplayer.get_unique_id()),
		"ready": main.world_params != null and (dedicated or me != null),
		"dedicated": dedicated,
		"players": players,
		"cuts": cuts,
		"cells": cells,
		"wood": wood,
		"mob": mob_name,
		"mob_states": seen,
		"mob_hp": watched_hp,
		"mob_present": present,
		"hitting": hitting,
		"errors": _errors.snapshot(),
	}))
	file.close()
	DirAccess.rename_absolute(out + ".tmp", out)
