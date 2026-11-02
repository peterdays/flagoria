extends SceneTree
## Hosts a saved world with cuts for test_cut_save_late_join in
## tests/saves/test_cut_save.gd. Run with `-- --port=N --save=PATH --out=PATH`:
## loads the save through MapGen.load_map_inputs, hosts it on port N the way
## the main menu's Host does, and every 100 ms writes to --out the host's cut
## list and, for each cut cell, what is drawn there and whether it blocks.
## Stops when PATH.stop (next to --out) exists, or after 60 s.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var port := 0
	var save := ""
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--save="):
			save = arg.trim_prefix("--save=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if port == 0 or save == "" or out == "" or change_scene_to_file("res://flagoria_main.tscn") != OK:
		printerr("cut_sync_probe: needs --port=N, --save=PATH, --out=PATH and the main scene")
		quit(1)
		return
	await process_frame
	await process_frame
	var main = current_scene
	var map_gen = root.get_node("MapGen")
	var error: String = map_gen.load_map_inputs(save)
	if error != "" or main.setup_server(map_gen.params.duplicate_params(), port) != OK:
		printerr("cut_sync_probe: could not host %s: %s" % [save, error])
		quit(1)
		return
	main.add_player(1)
	var world = main.get_node("World/worldMap")
	var deadline := Time.get_ticks_msec() + 60000
	var next_write := 0
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(out + ".stop"):
		if Time.get_ticks_msec() >= next_write:
			next_write = Time.get_ticks_msec() + 100
			_write(out, world)
		await process_frame
	quit(0)


static func cell_state(world, cell: Vector2i) -> Dictionary:
	## What a player meets on `cell`: the foliage tile, the decor under it
	## (a stump) and whether the cell is clear to walk. Draws its chunk first.
	var clear: bool = world.is_clear_ground(cell)
	var decor: Vector2i = world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, cell)
	var plant: Vector2i = world.get_cell_atlas_coords(1, cell)
	return {"plant": [plant.x, plant.y], "decor": [decor.x, decor.y], "clear": clear}


func _write(out: String, world) -> void:
	var cuts: Dictionary = world.cut_changes()
	var cells := {}
	for chunk in cuts:
		for key in cuts[chunk]:
			cells[key] = cell_state(world, WorldSave.parse_cell(key))
	var file := FileAccess.open(out + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify({"cuts": cuts, "cells": cells}))
	file.close()
	DirAccess.rename_absolute(out + ".tmp", out)
