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
