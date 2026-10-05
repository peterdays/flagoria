extends SceneTree
## Headless test entry point for CI.
## Run: godot --headless --path . --script res://tests/run_tests.gd
## Exit 0 on success, 1 on failure.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := 0
	failures += _test_smoke_true()
	failures += _test_map_characterization()
	if failures == 0:
		print("All tests passed.")
		quit(0)
	else:
		print("Tests failed: %s" % failures)
		quit(1)


func _test_smoke_true() -> int:
	## Trivial sanity check that the headless runner executes and reports.
	print("-- test_smoke_true")
	if true:
		print("PASS test_smoke_true")
		return 0
	printerr("FAIL test_smoke_true")
	return 1


func _test_map_characterization() -> int:
	## Fixed MapGenParams seeds + generate_chunk; compare atlas coords on layers 0 and 1.
	print("-- test_map_characterization")
	const CHUNK_POS := Vector2(0, 0)

	# cell -> [layer0 atlas, layer1 atlas]  (Vector2i(-1,-1) = empty)
	var expected := {
		Vector2i(-16, -16): [Vector2i(5, 6), Vector2i(-1, -1)],
		Vector2i(12, 6): [Vector2i(5, 4), Vector2i(-1, -1)],
		Vector2i(13, 6): [Vector2i(5, 1), Vector2i(-1, -1)],
		Vector2i(14, 6): [Vector2i(5, 0), Vector2i(-1, -1)],
		Vector2i(14, 11): [Vector2i(6, 0), Vector2i(-1, -1)],
		Vector2i(14, 7): [Vector2i(5, 1), Vector2i(7, 3)],
		Vector2i(0, 0): [Vector2i(5, 6), Vector2i(-1, -1)],
		Vector2i(8, -8): [Vector2i(5, 6), Vector2i(-1, -1)],
		Vector2i(-8, 8): [Vector2i(5, 6), Vector2i(-1, -1)],
		Vector2i(15, 15): [Vector2i(5, 4), Vector2i(-1, -1)],
		Vector2i(15, 6): [Vector2i(6, 0), Vector2i(7, 3)],
	}

	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	if world == null:
		printerr("FAIL: World/worldMap missing")
		return 1

	var params = MapGenParams.make_defaults()
	params.altitude_seed = 2
	params.moisture_seed = 7
	params.temperature_seed = 12
	params.items_seed = 17
	world.apply_map_params(params)
	world.generate_chunk(CHUNK_POS)

	var fail := 0
	for cell in expected.keys():
		var want = expected[cell]
		var got0: Vector2i = world.get_cell_atlas_coords(0, cell)
		var got1: Vector2i = world.get_cell_atlas_coords(1, cell)
		if got0 != want[0] or got1 != want[1]:
			printerr(
				"FAIL cell=%s expected l0=%s l1=%s got l0=%s l1=%s"
				% [cell, want[0], want[1], got0, got1]
			)
			fail += 1

	if fail == 0:
		print("PASS test_map_characterization (%s cells)" % expected.size())
	scene.queue_free()
	return fail
