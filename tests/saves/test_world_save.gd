extends "res://tests/helpers/test_helpers.gd"
## One save in memory (Scripts/world_save.gd) and its versions.


func _test_world_save_round_trip() -> int:
	## A world save keeps its generation inputs, change sections and player
	## section through save + load, says which format and version it is, and
	## an unchanged world stays small: inputs only, no terrain.
	print("-- test_world_save_round_trip")
	var fail := 0
	var params := MapGenParams.make_defaults()
	params.ensure_seeds()
	var world := WorldSave.new(params)
	world.tile_edits["0,0"] = {"3,4": "SAND"}
	world.object_changes["-1,2"] = {"-20,70": {"removed": true}}
	world.structures["1,1"] = {"40,40": {"name": "guard_post"}}
	world.player = {"position": [12.5, -3.25]}  # JSON numbers read back as floats
	var saved := MapSave.save_world(world, "test_world_round_trip")
	var loaded := MapSave.load_world(saved["path"])
	var text := FileAccess.get_file_as_string(saved["path"])
	DirAccess.remove_absolute(saved["path"])
	if saved["error"] != "" or loaded["error"] != "":
		printerr("FAIL world_save_round_trip save=%s load=%s" % [saved["error"], loaded["error"]])
		return 1
	var got: WorldSave = loaded["world"]
	var header = JSON.parse_string(text)
	if header["format"] != MapSave.FORMAT_ID or header["format_version"] != MapSave.FORMAT_VERSION or loaded["version"] != MapSave.FORMAT_VERSION:
		printerr("FAIL world_save_round_trip header format=%s version=%s" % [header["format"], header["format_version"]])
		fail += 1
	if got.params.to_dict() != params.to_dict():
		printerr("FAIL world_save_round_trip params changed")
		fail += 1
	for section in ["tile_edits", "object_changes", "structures", "player"]:
		if got.get(section) != world.get(section):
			printerr("FAIL world_save_round_trip %s saved=%s loaded=%s" % [section, world.get(section), got.get(section)])
			fail += 1

	var empty := MapSave.save_map(params, "test_world_empty")
	var size := FileAccess.get_file_as_bytes(empty["path"]).size()
	var reloaded := MapSave.load_world(empty["path"])
	DirAccess.remove_absolute(empty["path"])
	var sections_empty: bool = reloaded["error"] == "" and reloaded["world"].world_to_dict().values().all(func(s): return s.is_empty()) \
			and reloaded["world"].player.is_empty()
	if size > 2048 or not sections_empty:
		printerr("FAIL world_save_round_trip unchanged world: %d bytes (budget 2048), sections empty=%s" % [size, sections_empty])
		fail += 1
	if fail == 0:
		print("PASS test_world_save_round_trip (unchanged world %d bytes)" % size)
	return fail


func _test_world_save_version_check() -> int:
	## The current version loads; a newer version, an unknown version, another
	## format and a malformed change section are refused with a clear error.
	print("-- test_world_save_version_check")
	var fail := 0
	var params := '"params": {"altitude_seed": 7}'
	var cases := {
		"test_ws_current": ['{"format": "flagoria-world", "format_version": 2, %s, "world": {}, "player": {}}' % params, ""],
		"test_ws_no_sections": ['{"format": "flagoria-world", "format_version": 2, %s}' % params, ""],
		"test_ws_future": ['{"format": "flagoria-world", "format_version": 3, %s}' % params, "version 3, from a newer build"],
		"test_ws_fraction": ['{"format": "flagoria-world", "format_version": 1.5, %s}' % params, "unknown map save version"],
		"test_ws_other_format": ['{"format": "other", "format_version": 2, %s}' % params, "not a world save"],
		"test_ws_no_format": ['{"format_version": 2, %s}' % params, "not a world save"],
		"test_ws_bad_section": [
			'{"format": "flagoria-world", "format_version": 2, %s, "world": {"tile_edits": {"0,0": 5}}}' % params,
			"world.tile_edits[0,0] is not an object",
		],
		"test_ws_bad_player": ['{"format": "flagoria-world", "format_version": 2, %s, "player": []}' % params, "not an object"],
	}
	DirAccess.make_dir_recursive_absolute(MapSave.SAVE_DIR)
	for save_name in cases.keys():
		var path := MapSave.path_for(save_name)
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(cases[save_name][0])
		file.close()
		var result := MapSave.load_world(path)
		DirAccess.remove_absolute(path)
		var want: String = cases[save_name][1]
		var ok: bool = (result["error"] == "" and result["world"] != null and result["world"].params.altitude_seed == 7) if want == "" \
				else (result["world"] == null and want in result["error"])
		if not ok:
			printerr("FAIL world_save_version_check %s error=%s want %s" % [save_name, result["error"], want if want != "" else "a load"])
			fail += 1
	if fail == 0:
		print("PASS test_world_save_version_check")
	return fail


func _test_world_save_migrates_v1() -> int:
	## Every format version has a fixture in tests/fixtures/ that still loads.
	## A version 1 map save (inputs only, written by the first map save code)
	## loads with the same inputs and empty change sections, and saving it
	## again writes the current version.
	print("-- test_world_save_migrates_v1")
	var fail := 0
	for version in range(1, MapSave.FORMAT_VERSION + 1):
		var fixture := "res://tests/fixtures/world_save_v%d.json" % version
		var loaded := MapSave.load_world(fixture)
		if loaded["error"] != "" or loaded["version"] != version:
			printerr("FAIL world_save_migrates_v1 %s error=%s version=%s" % [fixture, loaded["error"], loaded["version"]])
			fail += 1
			continue
		var world: WorldSave = loaded["world"]
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture))["params"]
		for key in raw:
			if world.params.get(key) != raw[key]:
				printerr("FAIL world_save_migrates_v1 %s %s=%s want %s" % [fixture, key, world.params.get(key), raw[key]])
				fail += 1
		if not world.world_to_dict().values().all(func(s): return s.is_empty()) or not world.player.is_empty():
			printerr("FAIL world_save_migrates_v1 %s change sections not empty" % fixture)
			fail += 1
		var saved := MapSave.save_world(world, "test_ws_migrated_v%d" % version)
		var again := MapSave.load_world(saved["path"])
		DirAccess.remove_absolute(saved["path"])
		if again["error"] != "" or again["version"] != MapSave.FORMAT_VERSION or again["world"].params.to_dict() != world.params.to_dict():
			printerr("FAIL world_save_migrates_v1 %s re-save error=%s version=%s" % [fixture, again["error"], again["version"]])
			fail += 1
	if fail == 0:
		print("PASS test_world_save_migrates_v1 (fixtures v1 to v%d)" % MapSave.FORMAT_VERSION)
	return fail
