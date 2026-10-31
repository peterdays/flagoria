extends "res://tests/helpers/test_helpers.gd"
## Tree stumps across chunk redraws, and regrowth.


func _test_cut_tree_stays_stump() -> int:
	## A cut tree stays a stump when its chunk is drawn again, and predict_cell
	## and predicted_clear see the stump, so mobs treat the cell as open ground.
	print("-- test_cut_tree_stays_stump")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var fail := 0
	var tree := Vector2i(1 << 20, 0)
	var seed_value := 0
	for s in [11, 42, 7, 1, 99, 3, 5]:
		world.apply_map_params(_spawn_params(s, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell in world.get_used_cells(1):
			if world.has_tree(cell):
				tree = cell
				seed_value = s
				break
		if seed_value != 0:
			break
	if tree.x == 1 << 20:
		printerr("FAIL cut_tree_stays_stump: no tree near the origin on any seed")
		scene.queue_free()
		return 1
	world.predict_cell(tree)  # cached before the cut
	if not world.cut_choppable(tree) or world.cut_choppable(tree):
		printerr("FAIL cut_tree_stays_stump: cut_choppable did not cut %s exactly once" % tree)
		fail += 1
	world.generate_chunk(Vector2(0, 0))
	if world.has_tree(tree) or world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, tree) != TileCatalog.STUMP:
		printerr("FAIL cut_tree_stays_stump: %s grew back after the chunk was drawn again" % tree)
		fail += 1
	if world.predict_cell(tree)[1] != TileCatalog.STUMP or not world.predicted_clear(tree) or not world.is_clear_ground(tree):
		printerr("FAIL cut_tree_stays_stump: predict_cell %s for the stump" % [world.predict_cell(tree)])
		fail += 1
	world.apply_map_params(_spawn_params(seed_value, 0.0))
	world.generate_chunk(Vector2(0, 0))
	if not world.has_tree(tree):
		printerr("FAIL cut_tree_stays_stump: a new map kept the stump at %s" % tree)
		fail += 1
	scene.queue_free()
	if fail == 0:
		print("PASS test_cut_tree_stays_stump")
	return fail


func _test_tree_regrows() -> int:
	## A stump turns back into its tree once regrow_delay seconds of play have
	## passed since the cut, not before, and not while a player stands on it:
	## the same tree, with its collision, and predict_cell sees it again.
	print("-- test_tree_regrows")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var fail := 0
	var tree := Vector2i(1 << 20, 0)
	for s in [11, 42, 7, 1, 99, 3, 5]:
		world.apply_map_params(_spawn_params(s, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell in world.get_used_cells(1):
			if world.has_tree(cell):
				tree = cell
				break
		if tree.x != 1 << 20:
			break
	if tree.x == 1 << 20:
		printerr("FAIL tree_regrows: no tree near the origin on any seed")
		scene.queue_free()
		return 1
	var atlas: Vector2i = world.get_cell_atlas_coords(1, tree)
	var is_stump := func() -> bool:
		return not world.has_tree(tree) and world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, tree) == TileCatalog.STUMP
	world.regrow_delay = 30.0
	world.play_time = 100.0
	world.cut_choppable(tree)
	# Not before the delay.
	world.play_time = 129.9
	if world.regrow_due() != 0 or not is_stump.call():
		printerr("FAIL tree_regrows: %s regrew before the delay" % tree)
		fail += 1
	# Not while a player stands on the stump.
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	player.position = world.to_global(world.map_to_local(tree))
	scene.get_node("World").add_child(player)
	await process_frame
	world.play_time = 200.0
	if not world.player_on_cell(tree) or world.regrow_due() != 0 or not is_stump.call():
		printerr("FAIL tree_regrows: %s regrew under the player" % tree)
		fail += 1
	# After the delay, once the player has moved off.
	player.position = world.to_global(world.map_to_local(tree + Vector2i(6, 6)))
	if world.player_on_cell(tree) or world.regrow_due() != 1:
		printerr("FAIL tree_regrows: %s did not regrow after the delay" % tree)
		fail += 1
	var top = world.get_cell_tile_data(1, tree)
	if world.get_cell_atlas_coords(1, tree) != atlas or world.get_cell_source_id(world.GROUND_DECOR_LAYER, tree) != -1 \
			or top == null or top.get_collision_polygons_count(0) == 0:
		printerr("FAIL tree_regrows: %s is %s after regrowing, want %s with collision and no stump"
				% [tree, world.get_cell_atlas_coords(1, tree), atlas])
		fail += 1
	if world.predict_cell(tree)[1] != atlas or world.predicted_clear(tree):
		printerr("FAIL tree_regrows: predict_cell %s after regrowing" % [world.predict_cell(tree)])
		fail += 1
	# It can be cut again, and the chunk keeps it a tree once regrown.
	world.generate_chunk(Vector2(0, 0))
	if not world.has_tree(tree) or not world.cut_choppable(tree):
		printerr("FAIL tree_regrows: %s cannot be cut again after regrowing" % tree)
		fail += 1
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_tree_regrows")
	return fail
