extends SceneTree
## Headless command line for maps, without the menu or a match:
##   godot --headless --path . --script res://tools/cli.gd -- map render --seed 42
## Commands and options: MapCli.USAGE. Prints to stdout, or writes --out.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var parsed := MapCli.parse(OS.get_cmdline_user_args())
	if parsed["error"] != "":
		printerr("error: %s\n%s" % [parsed["error"], MapCli.USAGE])
		quit(2)
		return
	var options: Dictionary = parsed["options"]
	var resolved := MapCli.params_for(options["params"], options["seed"])
	if resolved["error"] != "":
		printerr("error: " + resolved["error"])
		quit(1)
		return
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var rows := MapCli.generate(scene.get_node("World/worldMap"), resolved["params"])
	var text := MapCli.ascii(rows) if parsed["command"] == "map render" else MapCli.stats(rows)
	var code := 0
	if options["out"] == "":
		printraw(text)
	else:
		var file := FileAccess.open(options["out"], FileAccess.WRITE)
		if file == null:
			printerr("error: cannot write %s (error %s)" % [options["out"], FileAccess.get_open_error()])
			code = 1
		else:
			file.store_string(text)
			file.close()
	scene.queue_free()
	quit(code)
