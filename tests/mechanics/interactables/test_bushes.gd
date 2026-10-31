extends "res://tests/helpers/test_helpers.gd"
## Chopping a bush, and its stump and regrowth.


func _test_chop_bush() -> int:
	## A bush chops like a tree (#267): two hits at 140 ms and 460 ms, each
	## with a bush hit sound, the hit sheet drawn in place of the hidden bush
	## tile (its collision kept) and the leaves fx. At 560 ms it becomes a
	## walkable BUSH_STUMP with the break sound and the falling leaves, no
	## puff, and gives the bush's wood, less than a tree's. The hero boxed in
	## by bushes can then walk out through the cut one.
	print("-- test_chop_bush")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	var world = scene.get_node("World/worldMap")
	world.clear()
	for x in range(4, 16):
		for y in range(4, 14):
			world.set_cell(0, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
	var home := Vector2i(10, 10)
	for x in range(9, 12):
		for y in range(9, 12):
			if Vector2i(x, y) != home:
				world.set_cell(1, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.BUSH)
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	player.position = world.to_global(world.map_to_local(home))
	scene.get_node("World").add_child(player)
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	interaction.set_process(false)  # the test steps the chop clock itself
	var inventory: Inventory = scene.get_node("Inventory")
	var bush_type := InteractableCatalog.by_id("bush")
	var bush_wood := bush_type.amount_of(Inventory.WOOD)
	if bush_wood < 1 or bush_wood >= InteractableCatalog.by_id("tree").amount_of(Inventory.WOOD):
		printerr("FAIL chop_bush: bush wood %s is not less than a tree's" % bush_wood)
		fail += 1
	var bush := Vector2i(10, 9)
	var run_to := func(t: float) -> void:
		interaction.step_chop(t - maxf(interaction.chop_time, 0.0))
	var walks_up := func() -> bool:
		await physics_frame
		await physics_frame
		var body: CollisionShape2D = player.get_node("CollisionShape2D")
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = body.shape
		query.collision_mask = player.collision_mask
		query.exclude = [player.get_rid()]
		query.transform = Transform2D(0, player.global_position + body.position)
		query.motion = Vector2(0, -32)
		return world.get_world_2d().direct_space_state.cast_motion(query)[0] >= 1.0
	if await walks_up.call():
		printerr("FAIL chop_bush: the bush at %s does not block before the chop" % bush)
		fail += 1

	interaction.set_mode(Interaction.Mode.INTERACT)
	if not interaction.start_chop(bush) or interaction.chop_type != bush_type:
		printerr("FAIL chop_bush: could not start chopping the bush at %s" % bush)
		fail += 1
	run_to.call(0.15)
	if world.choppable(bush) != bush_type or world.get_cell_alternative_tile(1, bush) != Interaction.HIDDEN_ALT \
			or not interaction._hit.visible or interaction._hit.frame != 0 or not interaction._fx.visible \
			or interaction._fx.frame != 0 or interaction.sfx_log.size() != 1 \
			or not bush_type.hit_sounds.has(interaction.sfx_log[0]):
		printerr("FAIL chop_bush: first hit: alt %s, hit %s/%s, fx %s/%s, sounds %s"
				% [world.get_cell_alternative_tile(1, bush), interaction._hit.visible, interaction._hit.frame,
				interaction._fx.visible, interaction._fx.frame, interaction.sfx_log])
		fail += 1
	if await walks_up.call():
		printerr("FAIL chop_bush: the hidden bush tile lost its collision")
		fail += 1
	run_to.call(0.2)
	if interaction._hit.frame != 1 or interaction._fx.frame != 1:
		printerr("FAIL chop_bush: at 200 ms hit frame %s, fx frame %s" % [interaction._hit.frame, interaction._fx.frame])
		fail += 1
	run_to.call(0.3)
	if interaction._hit.visible or interaction._fx.visible or world.get_cell_alternative_tile(1, bush) != 0:
		printerr("FAIL chop_bush: the hit did not end by 300 ms")
		fail += 1
	run_to.call(0.55)
	if world.choppable(bush) != bush_type or inventory.count_of(Inventory.WOOD) != 0 or interaction.sfx_log.size() != 2:
		printerr("FAIL chop_bush: before 560 ms bush %s, wood %s, sounds %s"
				% [world.choppable(bush), inventory.count_of(Inventory.WOOD), interaction.sfx_log.size()])
		fail += 1
	run_to.call(0.57)
	if world.choppable(bush) != null or world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, bush) != TileCatalog.BUSH_STUMP \
			or inventory.count_of(Inventory.WOOD) != bush_wood or interaction._puff.visible \
			or not interaction._fx.visible or interaction._fx.frame != 2 or interaction._hit.visible \
			or interaction.sfx_log.size() != 3 or interaction.sfx_log[2] != bush_type.fell_sounds[0]:
		printerr("FAIL chop_bush: at 560 ms decor %s, wood %s, puff %s, fx %s/%s, sounds %s"
				% [world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, bush), inventory.count_of(Inventory.WOOD),
				interaction._puff.visible, interaction._fx.visible, interaction._fx.frame, interaction.sfx_log])
		fail += 1
	run_to.call(0.75)
	if not interaction._fx.visible or interaction._fx.frame != 3:
		printerr("FAIL chop_bush: at 750 ms fx %s/%s, want frame 3" % [interaction._fx.visible, interaction._fx.frame])
		fail += 1
	interaction.step_chop(1.0)
	if interaction.chopping() or interaction._fx.visible or inventory.count_of(Inventory.WOOD) != bush_wood:
		printerr("FAIL chop_bush: after the chop: chopping %s, fx %s, wood %s"
				% [interaction.chopping(), interaction._fx.visible, inventory.count_of(Inventory.WOOD)])
		fail += 1
	if not world.is_clear_ground(bush) or not await walks_up.call():
		printerr("FAIL chop_bush: the hero is still blocked by the BUSH_STUMP at %s" % bush)
		fail += 1
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_chop_bush")
	return fail


func _test_cut_bush_stays_stump_and_regrows() -> int:
	## A cut bush keeps its BUSH_STUMP when its chunk is drawn again (and
	## predict_cell sees it as open ground), then regrows into the same bush,
	## with its collision, once regrow_delay seconds of play have passed.
	print("-- test_cut_bush_stays_stump_and_regrows")
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")
	var fail := 0
	var bush_type := InteractableCatalog.by_id("bush")
	var bush := Vector2i(1 << 20, 0)
	for s in [11, 42, 7, 1, 99, 3, 5]:
		world.apply_map_params(_spawn_params(s, 0.0))
		world.generate_chunk(Vector2(0, 0))
		for cell in world.get_used_cells(1):
			if world.choppable(cell) == bush_type:
				bush = cell
				break
		if bush.x != 1 << 20:
			break
	if bush.x == 1 << 20:
		printerr("FAIL cut_bush_stays_stump_and_regrows: no bush near the origin on any seed")
		scene.queue_free()
		return 1
	world.predict_cell(bush)  # cached before the cut
	world.regrow_delay = 30.0
	world.play_time = 100.0
	if world.cut_choppable(bush) != bush_type or world.cut_choppable(bush) != null:
		printerr("FAIL cut_bush_stays_stump_and_regrows: cut_choppable did not cut %s exactly once" % bush)
		fail += 1
	world.generate_chunk(Vector2(0, 0))
	if world.choppable(bush) != null or world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, bush) != TileCatalog.BUSH_STUMP:
		printerr("FAIL cut_bush_stays_stump_and_regrows: %s grew back when the chunk was drawn again" % bush)
		fail += 1
	if world.predict_cell(bush)[1] != TileCatalog.BUSH_STUMP or not world.predicted_clear(bush) or not world.is_clear_ground(bush):
		printerr("FAIL cut_bush_stays_stump_and_regrows: predict_cell %s for the stump" % [world.predict_cell(bush)])
		fail += 1
	world.play_time = 129.9
	if world.regrow_due() != 0 or world.choppable(bush) != null:
		printerr("FAIL cut_bush_stays_stump_and_regrows: %s regrew before the delay" % bush)
		fail += 1
	world.play_time = 130.1
	if world.regrow_due() != 1:
		printerr("FAIL cut_bush_stays_stump_and_regrows: %s did not regrow after the delay" % bush)
		fail += 1
	var top = world.get_cell_tile_data(1, bush)
	if world.get_cell_atlas_coords(1, bush) != TileCatalog.BUSH or world.get_cell_source_id(world.GROUND_DECOR_LAYER, bush) != -1 \
			or top == null or top.get_collision_polygons_count(0) == 0 or world.predict_cell(bush)[1] != TileCatalog.BUSH:
		printerr("FAIL cut_bush_stays_stump_and_regrows: %s is %s after regrowing, want a BUSH with collision"
				% [bush, world.get_cell_atlas_coords(1, bush)])
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_cut_bush_stays_stump_and_regrows")
	return fail
