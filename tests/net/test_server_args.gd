extends "res://tests/helpers/test_helpers.gd"
## Server port and map params from command-line args.


func _test_server_port_from_args() -> int:
	## `-- --server [--port N]` picks the dedicated-server port; 0 means GUI launch.
	print("-- test_server_port_from_args")
	var main_script = load("res://flagoria_main.gd")
	var cases := [
		[[], 0],
		[["--port", "9799"], 0],
		[["--server"], 9786],
		[["--server", "--port", "9799"], 9799],
		[["--server", "--port=9799"], 9799],
		[["--server", "--port", "abc"], -1],
		[["--server", "--port"], -1],
		[["--server", "--port=0"], -1],
		[["--server", "--port", "65536"], -1],
	]
	var fail := 0
	for case in cases:
		var got: int = main_script.server_port_from_args(PackedStringArray(case[0]))
		if got != case[1]:
			printerr("FAIL server_port_from_args %s = %s, want %s" % [case[0], got, case[1]])
			fail += 1
	if fail == 0:
		print("PASS test_server_port_from_args (%s cases)" % cases.size())
	return fail


func _test_server_params_from_args() -> int:
	## `--params <file>` gives the dedicated server a map save to host; no
	## --params means the active params (null); a bad value is an error.
	print("-- test_server_params_from_args")
	var main_script = load("res://flagoria_main.gd")
	var params := MapGenParams.make_defaults()
	params.altitude_seed = 1101
	params.moisture_seed = 1102
	params.temperature_seed = 1103
	params.items_seed = 1104
	params.biome_seed = 1105
	params.water_max_alt = 0.125
	var saved := MapSave.save_map(params, "test_server_params")
	var path: String = saved["path"]
	var fail := 0
	for case in [
		[["--server"], ""],
		[["--server", "--params", path], ""],
		[["--server", "--params=" + ProjectSettings.globalize_path(path)], ""],
		[["--server", "--params"], "needs a map save"],
		[["--server", "--params", "--port=9799"], "needs a map save"],
		[["--server", "--params="], "needs a map save"],
		[["--server", "--params", "user://no_such_save.json"], "no map save"],
	]:
		var got: Dictionary = main_script.server_params_from_args(PackedStringArray(case[0]))
		var has_file: bool = case[0].size() > 1 and case[1] == ""
		var ok: bool = (got["error"] == "" if case[1] == "" else case[1] in got["error"])
		if ok and has_file:
			ok = got["params"] != null and got["params"].to_dict() == params.to_dict()
		elif ok:
			ok = got["params"] == null
		if not ok:
			printerr("FAIL server_params_from_args %s = %s" % [case[0], got])
			fail += 1
	DirAccess.remove_absolute(path)
	if fail == 0:
		print("PASS test_server_params_from_args")
	return fail


func _test_params_mount_copy() -> int:
	## A params file is a byte copy of a map save onto another path, which is
	## what the docker smoke mounts at /params/map.json. A current save is
	## gzip and loads from that copy. Version 1 and 2 files are plain JSON
	## and still load from a byte copy.
	print("-- test_params_mount_copy")
	var main_script = load("res://flagoria_main.gd")
	var fail := 0
	var copies: Array[String] = []
	var params := MapGenParams.make_defaults()
	params.altitude_seed = 43701
	params.moisture_seed = 43702
	params.temperature_seed = 43703
	params.items_seed = 43704
	params.biome_seed = 43705
	params.ensure_seeds()
	var saved := MapSave.save_map(params, "test_params_mount")
	if str(saved["error"]) != "":
		printerr("FAIL params_mount_copy save: %s" % saved["error"])
		return 1
	var src: String = saved["path"]
	var raw := FileAccess.get_file_as_bytes(src)
	if raw.size() < 2 or raw[0] != 0x1f or raw[1] != 0x8b:
		printerr("FAIL params_mount_copy current save is not gzip")
		fail += 1
	else:
		var mounted := _write_temp_bytes(raw)
		copies.append(mounted)
		var got: Dictionary = main_script.server_params_from_args(PackedStringArray(["--server", "--params", mounted]))
		if got["error"] != "" or got["params"] == null or got["params"].to_dict() != params.to_dict():
			printerr("FAIL params_mount_copy byte copy error=%s" % got["error"])
			fail += 1
	for version in [1, 2]:
		var fixture := "res://tests/fixtures/world_save_v%d.json" % version
		var direct: Dictionary = main_script.server_params_from_args(PackedStringArray(["--params", fixture]))
		var copied := _write_temp_bytes(FileAccess.get_file_as_bytes(fixture))
		copies.append(copied)
		var via: Dictionary = main_script.server_params_from_args(PackedStringArray(["--params", copied]))
		var same: bool = direct["error"] == "" and via["error"] == "" and direct["params"] != null \
				and via["params"] != null and direct["params"].to_dict() == via["params"].to_dict()
		if not same:
			printerr("FAIL params_mount_copy v%s direct=%s copy=%s" % [version, direct["error"], via["error"]])
			fail += 1
	DirAccess.remove_absolute(src)
	for path in copies:
		DirAccess.remove_absolute(path)
	if fail == 0:
		print("PASS test_params_mount_copy")
	return fail


var _params_copy_n := 0


func _write_temp_bytes(bytes: PackedByteArray) -> String:
	## An absolute path outside user://, the shape of a mounted params file.
	_params_copy_n += 1
	var path := OS.get_temp_dir().path_join("flagoria_params_%d_%d.json" % [OS.get_process_id(), _params_copy_n])
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_buffer(bytes)
	handle.close()
	return path
