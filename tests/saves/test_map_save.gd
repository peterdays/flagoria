extends "res://tests/helpers/test_helpers.gd"
## Save files (Scripts/map_save.gd) and the saved maps list.


func _test_map_save_round_trip() -> int:
	## Every MapGenParams value survives save + load exactly, and the loaded
	## inputs regenerate the same origin chunk on layers 0 and 1. Float inputs
	## use all 17 significant digits.
	print("-- test_map_save_round_trip")
	var fail := 0
	var params = _pre_biome_defaults()
	var defaults: Dictionary = params.to_dict()
	for key in defaults.keys():
		if typeof(defaults[key]) == TYPE_INT:
			params.set(key, defaults[key] + 3)
		else:
			params.set(key, defaults[key] + 1.0 / 3.0)
	var saved = MapSave.save_map(params, "test_round_trip")
	var loaded = MapSave.load_map(saved["path"])
	if saved["error"] != "" or loaded["error"] != "":
		printerr("FAIL map_save_round_trip save=%s load=%s" % [saved["error"], loaded["error"]])
		return 1
	var want: Dictionary = params.to_dict()
	var got: Dictionary = loaded["params"].to_dict()
	for key in want.keys():
		if typeof(got[key]) != typeof(want[key]) or got[key] != want[key]:
			printerr("FAIL map_save_round_trip %s saved=%s loaded=%s" % [key, want[key], got[key]])
			fail += 1
	DirAccess.remove_absolute(saved["path"])

	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var map_gen = root.get_node("MapGen")
	var active_params = map_gen.params
	var original = _pre_biome_defaults()
	original.altitude_seed = 4242
	original.moisture_seed = 5252
	original.temperature_seed = 6262
	original.items_seed = 7272
	original.biome_seed = 8282
	original.water_max_alt = 0.4
	original.sand_max_alt = 0.48
	map_gen.params = original
	var save_error: String = map_gen.save_map_inputs("test_same_map")
	map_gen.params = _pre_biome_defaults()
	var load_error: String = map_gen.load_map_inputs(MapSave.path_for("test_same_map"))
	var reloaded: MapGenParams = map_gen.params
	map_gen.params = active_params
	DirAccess.remove_absolute(MapSave.path_for("test_same_map"))
	if save_error != "" or load_error != "":
		printerr("FAIL map_save_round_trip save=%s load=%s" % [save_error, load_error])
		scene.queue_free()
		return fail + 1

	var cells := {}
	world.apply_map_params(original)
	world.generate_chunk(Vector2(0, 0))
	for cell in world.get_used_cells(0):
		cells[cell] = [world.get_cell_atlas_coords(0, cell), world.get_cell_atlas_coords(1, cell)]
	world.apply_map_params(reloaded)
	world.generate_chunk(Vector2(0, 0))
	var mismatched := 0
	for cell in cells.keys():
		if cells[cell] != [world.get_cell_atlas_coords(0, cell), world.get_cell_atlas_coords(1, cell)]:
			mismatched += 1
	if cells.size() == 0 or mismatched > 0 or world.get_used_cells(0).size() != cells.size():
		printerr("FAIL map_save_round_trip regenerated chunk: %s of %s cells differ" % [mismatched, cells.size()])
		fail += 1
	scene.queue_free()
	if fail == 0:
		print("PASS test_map_save_round_trip (%s values, %s cells)" % [want.size(), cells.size()])
	return fail


func _test_map_save_rejects_bad_files() -> int:
	## Unknown versions, malformed files and unresolved seeds give clear errors.
	print("-- test_map_save_rejects_bad_files")
	var fail := 0
	var unresolved = MapSave.save_map(_pre_biome_defaults(), "test_unresolved")
	if not "unresolved" in unresolved["error"] or FileAccess.file_exists(MapSave.path_for("test_unresolved")):
		printerr("FAIL map_save_rejects_bad_files unresolved seeds: %s" % unresolved["error"])
		fail += 1

	var cases := {
		"test_future_version": ['{"format_version": 99, "params": {}}', "version 99"],
		"test_no_version": ['{"params": {}}', "no format_version"],
		"test_not_json": ["not json", "invalid JSON"],
		"test_no_params": ['{"format_version": 1}', "no params"],
	}
	DirAccess.make_dir_recursive_absolute(MapSave.SAVE_DIR)
	for save_name in cases.keys():
		var path := MapSave.path_for(save_name)
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(cases[save_name][0])
		file.close()
		var result = MapSave.load_map(path)
		DirAccess.remove_absolute(path)
		if result["params"] != null or not cases[save_name][1] in result["error"]:
			printerr(
				"FAIL map_save_rejects_bad_files %s error=%s want it to mention %s"
				% [save_name, result["error"], cases[save_name][1]]
			)
			fail += 1
	if fail == 0:
		print("PASS test_map_save_rejects_bad_files")
	return fail


func _test_map_save_needs_every_seed() -> int:
	## A save must hold every seed the world used. Any MapGenParams seed left
	## at 0 would be re-rolled on load, so saving refuses it and writes no file.
	print("-- test_map_save_needs_every_seed")
	var fail := 0
	var seed_keys: Array[String] = []
	for key in MapGenParams.make_defaults().to_dict().keys():
		if key.ends_with("_seed"):
			seed_keys.append(key)
	if not "biome_seed" in seed_keys:
		printerr("FAIL map_save_needs_every_seed: biome_seed not among %s" % [seed_keys])
		fail += 1
	for unset_key in seed_keys:
		var params := MapGenParams.make_defaults()
		for key in seed_keys:
			params.set(key, 0 if key == unset_key else 17)
		var save_name: String = "test_unset_" + unset_key
		DirAccess.remove_absolute(MapSave.path_for(save_name))
		var result = MapSave.save_map(params, save_name)
		var written := FileAccess.file_exists(MapSave.path_for(save_name))
		DirAccess.remove_absolute(MapSave.path_for(save_name))
		if not unset_key in result["error"] or written:
			printerr("FAIL map_save_needs_every_seed %s=0: error=%s file written=%s" % [unset_key, result["error"], written])
			fail += 1
	if fail == 0:
		print("PASS test_map_save_needs_every_seed (%s seeds)" % seed_keys.size())
	return fail


func _test_saved_maps_list_rename_delete() -> int:
	## The saved-maps list shows each save's name and date, newest first, and
	## rename and delete act on the right file, and a name that points outside
	## the saves folder is refused. Runs in a temporary directory.
	print("-- test_saved_maps_list_rename_delete")
	var fail := 0
	var base := OS.get_temp_dir().path_join("flagoria_test_saved_maps_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var dir := base + "/saves/"
	if MapSave.list_saves(dir) != []:
		printerr("FAIL saved_maps: missing directory lists %s, want []" % [MapSave.list_saves(dir)])
		fail += 1
	DirAccess.make_dir_recursive_absolute(dir)
	# [name, modified time]; a non-save file must not be listed.
	var files := [["Alpha", 1000], ["beta", 3000], ["Gamma", 2000]]
	for entry in files:
		var file := FileAccess.open(dir + entry[0] + ".json", FileAccess.WRITE)
		file.store_string('{"format_version": 1, "params": {}}')
		file.close()
		# Godot cannot set a file's modified time; touch sets it to the second.
		OS.execute("touch", ["-d", "@%d" % entry[1], ProjectSettings.globalize_path(dir + entry[0] + ".json")])
	FileAccess.open(dir + "notes.txt", FileAccess.WRITE).close()

	var listed: Array[Dictionary] = MapSave.list_saves(dir)
	var names: Array = listed.map(func(row): return row["name"])
	if names != ["beta", "Gamma", "Alpha"] or listed[0]["modified"] != 3000 or listed[0]["path"] != dir + "beta.json":
		printerr("FAIL saved_maps: listed %s, want beta, Gamma, Alpha newest first" % [listed])
		fail += 1

	var cases := [
		[["Gamma", "Delta"], "", ["beta", "Delta", "Alpha"]],
		[["Delta", "Alpha"], "already", null],
		[["missing", "Other"], "no map save", null],
		[["Delta", "  "], "name", null],
	]
	for case in cases:
		var err: String = MapSave.rename_save(case[0][0], case[0][1], dir)
		var after: Array = MapSave.list_saves(dir).map(func(row): return row["name"])
		if (err != "" if case[1] == "" else not case[1] in err) or (case[2] != null and after != case[2]):
			printerr("FAIL saved_maps: rename %s -> %s gave error=%s list=%s" % [case[0][0], case[0][1], err, after])
			fail += 1
	if FileAccess.get_file_as_string(dir + "Delta.json") != '{"format_version": 1, "params": {}}':
		printerr("FAIL saved_maps: renamed save lost its contents")
		fail += 1

	var delete_error: String = MapSave.delete_save("beta", dir)
	var missing_error: String = MapSave.delete_save("beta", dir)
	var left: Array = MapSave.list_saves(dir).map(func(row): return row["name"])
	if delete_error != "" or not "no map save" in missing_error or left != ["Delta", "Alpha"]:
		printerr("FAIL saved_maps: delete gave %s / %s, list %s" % [delete_error, missing_error, left])
		fail += 1

	# A decoy save beside the saves folder: "../x" must not reach it.
	var decoy := base + "/x.json"
	FileAccess.open(decoy, FileAccess.WRITE).close()
	var escapes := {
		"delete ../x": MapSave.delete_save("../x", dir),
		"rename ../x": MapSave.rename_save("../x", "y", dir),
	}
	for what in escapes:
		if not "not a map save name" in escapes[what] or not FileAccess.file_exists(decoy) or FileAccess.file_exists(dir + "y.json"):
			printerr("FAIL saved_maps: %s gave error=%s, decoy kept=%s" % [what, escapes[what], FileAccess.file_exists(decoy)])
			fail += 1

	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + name)
	DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(decoy)
	DirAccess.remove_absolute(base)
	if fail == 0:
		print("PASS test_saved_maps_list_rename_delete")
	return fail


func _test_biome_seed_panel_round_trip() -> int:
	## A biome_seed above 2^31 - 1 (randi() returns up to 2^32 - 1) survives the
	## Map Settings panel unchanged and has its own seed row, not a SpinBox.
	print("-- test_biome_seed_panel_round_trip")
	var fail := 0
	var big := 4000000000
	var params = _pre_biome_defaults()
	params.biome_seed = big
	var map_gen = root.get_node("MapGen")
	var saved_params = map_gen.params
	map_gen.params = params
	var panel = load("res://map_admin_panel.tscn").instantiate()
	root.add_child(panel)
	map_gen.params = saved_params
	panel.load_from_params(params)
	if panel._spin_boxes.has("biome_seed"):
		printerr("FAIL biome_seed_panel: biome_seed has a SpinBox row")
		fail += 1
	if panel.seed_biome.text != str(big):
		printerr("FAIL biome_seed_panel: row shows %s want %s" % [panel.seed_biome.text, big])
		fail += 1
	var out = _pre_biome_defaults()
	panel.apply_to_params(out)
	if out.biome_seed != big:
		printerr("FAIL biome_seed_panel: round-trip %s want %s" % [out.biome_seed, big])
		fail += 1
	panel.queue_free()
	if fail == 0:
		print("PASS test_biome_seed_panel_round_trip")
	return fail
