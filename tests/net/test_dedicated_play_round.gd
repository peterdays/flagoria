extends "res://tests/helpers/test_helpers.gd"
## Two clients on a dedicated server: one cut, then one sword kill.
## Movement sync stays in test_two_player_smoke. This does not click Host.

## launch.sh --seed 5. A bush and a slime sit inside the spawn chunk.
const ROUND_SEED := 5


func _test_dedicated_play_round() -> int:
	## Server has no World child "1". Client A cuts one plant; A receives the
	## wood and both clients see that plant removed. A then kills one mob;
	## B sees the hurt state and the death. Time cost: about 8–20 s.
	print("-- test_dedicated_play_round")
	await process_frame
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("CanvasLayer2/MainMenu").hide()
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	var params: MapGenParams = MapGenParams.make_defaults()
	params.altitude_seed = ROUND_SEED
	params.moisture_seed = ROUND_SEED + 1
	params.temperature_seed = ROUND_SEED + 2
	params.items_seed = ROUND_SEED + 3
	params.biome_seed = ROUND_SEED + 4
	params.ensure_seeds()
	world.apply_map_params(params)
	var spawn: Vector2i = world.resolve_player_spawn()
	var plant := Vector2i(999999, 999999)
	var plant_id := ""
	for r in range(1, 15):
		var found := false
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cell := spawn + Vector2i(dx, dy)
				var type = InteractableCatalog.type_at(world.predict_cell(cell)[1])
				if type != null and (type.id == "tree" or type.id == "bush"):
					plant = cell
					plant_id = type.id
					found = true
					break
			if found:
				break
		if found:
			break
	var rate: float = root.get_node("GameSettings").mob_rate
	var plan: Array = MobSpawner.plan(world, spawn, params.altitude_seed, rate)
	var mob_i := -1
	var mob_d := 99
	for i in plan.size():
		var c: Vector2i = plan[i]["cell"]
		var d := maxi(absi(c.x - spawn.x), absi(c.y - spawn.y))
		if d <= 14 and d < mob_d:
			mob_d = d
			mob_i = i
	scene.queue_free()
	await process_frame
	var port := _free_udp_port()
	if plant_id == "" or mob_i < 0 or port == 0:
		printerr("FAIL dedicated_play_round seed %s plant %s mob %s port %s" % [ROUND_SEED, plant, mob_i, port])
		return 1
	var saved := MapSave.save_map(params, "test_dedicated_play_%d_%d" % [OS.get_process_id(), port])
	if saved["error"] != "":
		printerr("FAIL dedicated_play_round could not save the map: %s" % saved["error"])
		return 1
	var mob_name := "mob_%d" % mob_i
	var yield_wood: int = InteractableCatalog.by_id(plant_id).amount_of(Inventory.WOOD)
	var cell_key := WorldSave.cell_key(plant)
	var dir := OS.get_user_data_dir().path_join("dedicated_play_%d_%d" % [OS.get_process_id(), port])
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var outs: Array[String] = []
	var pids: Array[int] = []
	var launch := func(extra: Array) -> void:
		outs.append(dir.path_join("p%d.json" % outs.size()))
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"),
				"--script", "res://tests/dedicated_play_probe.gd", "--",
				"--port=%d" % port, "--out=" + outs[-1], "--cells=" + cell_key, "--mob=" + mob_name]
		args.append_array(extra)
		pids.append(OS.create_process(OS.get_executable_path(), args))
	var read := func(i: int) -> Dictionary:
		var text := FileAccess.get_file_as_string(outs[i]) if FileAccess.file_exists(outs[i]) else ""
		var data = JSON.parse_string(text) if text != "" else null
		return data if data is Dictionary else {}
	var wait_for := func(cond: Callable, ms: int) -> bool:
		var until := Time.get_ticks_msec() + ms
		while Time.get_ticks_msec() < until and not cond.call():
			await process_frame
		return cond.call()
	var fail := 0
	launch.call(["--dedicated", "--rate=%s" % rate, "--save=" + ProjectSettings.globalize_path(saved["path"])])
	if not await wait_for.call(func() -> bool: return read.call(0).get("ready", false), 30000):
		printerr("FAIL dedicated_play_round server did not listen: %s" % read.call(0))
		fail = 1
	else:
		launch.call([])
		launch.call([])
		var spawned := func() -> bool:
			if not read.call(1).get("ready", false) or not read.call(2).get("ready", false):
				return false
			var a: String = read.call(1).get("id", "")
			var b: String = read.call(2).get("id", "")
			if a in ["", "0", "1"] or b in ["", "0", "1"] or a == b:
				return false
			for viewer in [1, 2]:
				var who: Array = read.call(viewer).get("players", [])
				if not (a in who and b in who):
					return false
			return true
		if not await wait_for.call(spawned, 30000):
			printerr("FAIL dedicated_play_round clients did not both spawn: server %s A %s B %s"
					% [read.call(0), read.call(1), read.call(2)])
			fail = 1
		elif "1" in read.call(0).get("players", []):
			printerr("FAIL dedicated_play_round server has a local player 1: %s" % read.call(0))
			fail = 1
		else:
			var drawn := func() -> bool:
				for i in [1, 2]:
					var cell = read.call(i).get("cells", {}).get(cell_key)
					if cell == null or cell["plant"] == [-1, -1]:
						return false
				return true
			if not await wait_for.call(drawn, 10000):
				printerr("FAIL dedicated_play_round plant %s %s was not drawn on both clients: A %s B %s"
						% [plant_id, plant, read.call(1).get("cells", {}), read.call(2).get("cells", {})])
				fail = 1
			else:
				var order := FileAccess.open(outs[1] + ".cut", FileAccess.WRITE)
				order.store_string(cell_key)
				order.close()
				var removed := func() -> bool:
					if int(read.call(1).get("wood", 0)) != yield_wood or int(read.call(2).get("wood", -1)) != 0:
						return false
					for i in [0, 1, 2]:
						if not (cell_key in read.call(i).get("cuts", [])):
							return false
					for i in [1, 2]:
						var cell = read.call(i).get("cells", {}).get(cell_key)
						if cell == null or cell["clear"] != true or int(cell["plant"][0]) != -1:
							return false
					return true
				if not await wait_for.call(removed, 10000):
					printerr("FAIL dedicated_play_round cut %s %s yield %s: server %s A %s B %s"
							% [plant_id, plant, yield_wood, read.call(0), read.call(1), read.call(2)])
					fail = 1
				else:
					FileAccess.open(outs[1] + ".hit", FileAccess.WRITE).close()
					var killed := func() -> bool:
						for i in [1, 2]:
							var states: Array[int] = []
							for state in read.call(i).get("mob_states", []):
								states.append(int(state))
							if not (Mob.State.HURT in states and Mob.State.DYING in states):
								return false
							if read.call(i).get("mob_present", true):
								return false
						return true
					if not await wait_for.call(killed, 20000):
						printerr("FAIL dedicated_play_round %s not seen hurt and dead by both clients: A %s B %s"
								% [mob_name, read.call(1), read.call(2)])
						fail = 1
		for i in outs.size():
			var errors: Array = read.call(i).get("errors", [])
			if not errors.is_empty():
				printerr("FAIL dedicated_play_round peer %d logged errors: %s" % [i, errors])
				fail = 1
	for out in outs:
		FileAccess.open(out + ".stop", FileAccess.WRITE).close()
	await wait_for.call(func() -> bool:
		for pid in pids:
			if OS.is_process_running(pid):
				return false
		return true, 10000)
	for pid in pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	_remove_dir(dir)
	DirAccess.remove_absolute(saved["path"])
	if fail == 0:
		print("PASS test_dedicated_play_round (%s %s cut, wood %s; %s hurt and dead on both clients; server players %s)"
				% [plant_id, plant, yield_wood, mob_name, read.call(0).get("players", [])])
	return fail
