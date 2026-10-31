extends "res://tests/helpers/test_helpers.gd"
## Headless map commands (tools/map_cli.gd).


func _test_map_cli_render_and_stats() -> int:
	## tools/cli.gd `map render` matches tests/golden/map_render_seed42.txt,
	## more water_max_alt draws more water, `map stats` is JSON and repeats
	## byte for byte, and bad input gives an error instead of a random map.
	print("-- test_map_cli_render_and_stats")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var params: MapGenParams = MapCli.params_for("default", "42")["params"]
	var rendered := MapCli.ascii(MapCli.generate(world, params))
	var golden := FileAccess.get_file_as_string("res://tests/golden/map_render_seed42.txt")
	if rendered != golden:
		printerr("FAIL map_cli: seed 42 render differs from the golden file; got:\n%s" % rendered)
		fail += 1
	params.water_max_alt += 0.1
	var wetter := MapCli.ascii(MapCli.generate(world, params))
	if wetter.count("~") <= rendered.count("~"):
		printerr("FAIL map_cli: water_max_alt +0.1 drew %s water cells, was %s" % [wetter.count("~"), rendered.count("~")])
		fail += 1

	var first := MapCli.stats(MapCli.generate(world, MapCli.params_for("default", "42")["params"]))
	var second := MapCli.stats(MapCli.generate(world, MapCli.params_for("default", "42")["params"]))
	var data = JSON.parse_string(first)
	if first != second or not data is Dictionary or data["tiles"].get("water", 0) != golden.count("~") \
			or data["land_cells"] + data["water_cells"] != 32 * 32 or data["islands"] < 1:
		printerr("FAIL map_cli: stats not stable or wrong:\n%s\n%s" % [first, second])
		fail += 1

	for case in [
		[["map", "draw"], "unknown command"],
		[["map", "render", "--seed"], "bad option"],
		[["map", "render", "--format", "png"], "ascii only"],
	]:
		var parsed := MapCli.parse(PackedStringArray(case[0]))
		if not case[1] in parsed["error"]:
			printerr("FAIL map_cli: %s gave error '%s', want '%s'" % [case[0], parsed["error"], case[1]])
			fail += 1
	for case in [["default", "", "is 0 (random)"], ["default", "abc", "--seed"], ["res://no_such_save.json", "7", "no map save"]]:
		var resolved := MapCli.params_for(case[0], case[1])
		if resolved["params"] != null or not case[2] in resolved["error"]:
			printerr("FAIL map_cli: params %s seed '%s' gave '%s', want '%s'" % [case[0], case[1], resolved["error"], case[2]])
			fail += 1
	scene.queue_free()
	if fail == 0:
		print("PASS test_map_cli_render_and_stats")
	return fail
