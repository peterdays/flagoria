extends "res://tests/helpers/test_helpers.gd"
## Chopping a tree with two hits.


func _test_chop_tree_two_hits() -> int:
	## A tap chops one tree (#237): the hero faces it and swings twice, each
	## impact (140 ms and 460 ms) is a hit, and one hit does not fell it. At
	## 560 ms the tree becomes a stump under the puff and gives its wood, once.
	## Moving away or leaving interact mode mid-chop leaves the tree and gives
	## nothing; a tap mid-chop starts no second chop. Interact mode is off in
	## multiplayer, and a peer joining forces combat mode, which cancels too.
	print("-- test_chop_tree_two_hits")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var world = scene.get_node("World/worldMap")
	world.clear()
	for x in range(4, 16):
		for y in range(4, 14):
			world.set_cell(0, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
	world.set_cell(1, Vector2i(10, 8), TileCatalog.SOURCE_ID, TileCatalog.TREE)
	world.set_cell(1, Vector2i(18, 10), TileCatalog.SOURCE_ID, TileCatalog.TREE_PINE_SMALL)
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	player.position = world.to_global(world.map_to_local(Vector2i(10, 10)))
	scene.get_node("World").add_child(player)
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	interaction.set_process(false)  # the test steps the chop clock itself
	var inventory: Inventory = scene.get_node("Inventory")
	var vp: Viewport = scene.get_viewport()
	var hits: Array = []
	interaction.chop_hit.connect(func(cell: Vector2i, hit: int) -> void: hits.append([cell, hit]))
	var tap := func(cell: Vector2) -> void:
		for pressed in [true, false]:
			var e := InputEventScreenTouch.new()
			e.position = interaction.get_canvas_transform() * world.to_global(cell * 16.0)
			e.pressed = pressed
			vp.push_input(e, true)
	var tree := Vector2i(10, 8)
	var pine := Vector2i(18, 10)
	var run_to := func(t: float) -> void:  # step the chop clock up to t s
		interaction.step_chop(t - maxf(interaction.chop_time, 0.0))
	var chop_sprite: Sprite2D = player.get_node("ChopSprite")
	var walk_sprite: Sprite2D = player.get_node("Sprite2D")
	var tree_wood := InteractableCatalog.by_id("tree").amount_of(Inventory.WOOD)

	interaction.set_mode(Interaction.Mode.INTERACT)
	tap.call(Vector2(10.5, 8.5))
	if not interaction.chopping() or interaction.chop_cell != tree or not world.has_tree(tree):
		printerr("FAIL chop_tree_two_hits: the tap did not start chopping %s (or cut it at once)" % tree)
		fail += 1
	run_to.call(0.13)
	if not hits.is_empty():
		printerr("FAIL chop_tree_two_hits: a hit before the first impact: %s" % [hits])
		fail += 1
	run_to.call(0.15)
	# Up at the tree, on the impact column of the chop sheet.
	if hits != [[tree, 1]] or not world.has_tree(tree) or inventory.count_of(Inventory.WOOD) != 0 \
			or not chop_sprite.visible or walk_sprite.visible or chop_sprite.frame_coords != Vector2i(2, 3):
		printerr("FAIL chop_tree_two_hits: after one hit: hits %s, tree %s, wood %s, chop pose %s %s"
				% [hits, world.has_tree(tree), inventory.count_of(Inventory.WOOD), chop_sprite.visible, chop_sprite.frame_coords])
		fail += 1
	tap.call(Vector2(18.5, 10.5))  # mid-chop: the sweep already started, no second one
	run_to.call(0.47)
	if hits != [[tree, 1], [tree, 2]] or interaction.chop_cell != tree:
		printerr("FAIL chop_tree_two_hits: second impact hits %s, chopping %s" % [hits, interaction.chop_cell])
		fail += 1
	run_to.call(0.55)
	if not world.has_tree(tree) or inventory.count_of(Inventory.WOOD) != 0:
		printerr("FAIL chop_tree_two_hits: the tree fell before 560 ms")
		fail += 1
	run_to.call(0.57)
	if world.has_tree(tree) or world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, tree) != TileCatalog.STUMP \
			or inventory.count_of(Inventory.WOOD) != tree_wood or not interaction._puff.visible:
		printerr("FAIL chop_tree_two_hits: at 560 ms tree %s, wood %s, puff %s"
				% [world.has_tree(tree), inventory.count_of(Inventory.WOOD), interaction._puff.visible])
		fail += 1
	run_to.call(0.6)  # the hero is still recovering from the second chop
	if not interaction.chopping() or not chop_sprite.visible or chop_sprite.frame_coords != Vector2i(3, 3):
		printerr("FAIL chop_tree_two_hits: no recover pose at 600 ms: %s %s" % [chop_sprite.visible, chop_sprite.frame_coords])
		fail += 1
	run_to.call(0.7)
	interaction.step_chop(1.0)
	if interaction.chopping() or chop_sprite.visible or not walk_sprite.visible or interaction._puff.visible \
			or inventory.count_of(Inventory.WOOD) != tree_wood or hits.size() != 2 \
			or not world.has_tree(pine):
		printerr("FAIL chop_tree_two_hits: after the chop: chopping %s, chop pose %s, wood %s, hits %s"
				% [interaction.chopping(), chop_sprite.visible, inventory.count_of(Inventory.WOOD), hits])
		fail += 1
	# Moving away mid-chop cancels: no stump, no wood.
	tap.call(Vector2(18.5, 10.5))
	run_to.call(0.2)
	player.global_position += Vector2(8, 0)
	interaction.step_chop(1.0)
	if interaction.chopping() or not world.has_tree(pine) or inventory.count_of(Inventory.WOOD) != tree_wood or chop_sprite.visible:
		printerr("FAIL chop_tree_two_hits: moving away did not cancel the chop")
		fail += 1
	# Leaving interact mode mid-chop cancels too.
	if not interaction.start_chop(pine):
		printerr("FAIL chop_tree_two_hits: could not chop %s again" % pine)
		fail += 1
	run_to.call(0.5)
	interaction.set_mode(Interaction.Mode.COMBAT)
	interaction.step_chop(1.0)
	if interaction.chopping() or not world.has_tree(pine) or inventory.count_of(Inventory.WOOD) != tree_wood:
		printerr("FAIL chop_tree_two_hits: leaving interact mode did not cancel the chop")
		fail += 1
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_chop_tree_two_hits")
	return fail


func _test_chop_sheet_on_single_cut() -> int:
	## A finger on one tree plays the chop sheet, including a drag that only
	## holds that tree (a tap can drift past the 6px threshold). A drag whose
	## cone holds two trees queues both and plays each chop in turn. A move
	## of 4 viewport px stays a tap. Time cost: about 0.4 s in tools/verify.sh
	## (~1.5 s alone with --only=).
	print("-- test_chop_sheet_on_single_cut")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var world = scene.get_node("World/worldMap")
	world.clear()
	for x in range(4, 20):
		for y in range(4, 16):
			world.set_cell(0, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
	var tree_a := Vector2i(10, 8)
	var tree_b := Vector2i(14, 8)
	var tree_c := Vector2i(10, 6)
	world.set_cell(1, tree_a, TileCatalog.SOURCE_ID, TileCatalog.TREE)
	world.set_cell(1, tree_b, TileCatalog.SOURCE_ID, TileCatalog.TREE)
	world.set_cell(1, tree_c, TileCatalog.SOURCE_ID, TileCatalog.TREE)
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	player.position = world.to_global(world.map_to_local(Vector2i(10, 10)))
	scene.get_node("World").add_child(player)
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	interaction.set_process(false)
	interaction.set_mode(Interaction.Mode.INTERACT)
	var vp: Viewport = scene.get_viewport()
	var chop_sprite: Sprite2D = player.get_node("ChopSprite")
	var walk_sprite: Sprite2D = player.get_node("Sprite2D")
	var at := func(cell: Vector2) -> Vector2:
		return interaction.get_canvas_transform() * world.to_global(cell * 16.0)
	var gesture := func(start: Vector2, end_pos: Vector2) -> void:
		var press := InputEventScreenTouch.new()
		press.position = start
		press.pressed = true
		vp.push_input(press, true)
		if start.distance_to(end_pos) > 0.5:
			var drag := InputEventScreenDrag.new()
			drag.position = end_pos
			vp.push_input(drag, true)
		var lift := InputEventScreenTouch.new()
		lift.position = end_pos
		lift.pressed = false
		vp.push_input(lift, true)
	var posed := func() -> bool:
		return interaction.chopping() and chop_sprite.visible and not walk_sprite.visible
	# 4 viewport px is still a tap: one chop, the other tree stands.
	var origin: Vector2 = at.call(Vector2(10.5, 8.5))
	gesture.call(origin, origin + Vector2(4, 0))
	if not posed.call() or interaction.chop_cell != tree_a or not world.has_tree(tree_b):
		printerr("FAIL chop_sheet_on_single_cut: 4px move chopping %s cell %s pose %s, tree b %s"
				% [interaction.chopping(), interaction.chop_cell, chop_sprite.visible, world.has_tree(tree_b)])
		fail += 1
	player.global_position += Vector2(8, 0)
	interaction.step_chop(0.05)
	player.global_position = world.to_global(world.map_to_local(Vector2i(10, 10)))
	# A drag aimed up the column queues both northern trees. The near one
	# poses. The far one stays up until that chop finishes. The side tree
	# is outside the cone.
	var feet: Vector2 = at.call(Vector2(10.5, 10.5))
	gesture.call(feet, at.call(Vector2(10.5, 10.5 - 68.0 / 16.0)))
	if not posed.call() or interaction.chop_cell != tree_a or not world.has_tree(tree_a) \
			or not world.has_tree(tree_c) or not world.has_tree(tree_b):
		printerr("FAIL chop_sheet_on_single_cut: queue start cell %s pose %s a %s c %s b %s"
				% [interaction.chop_cell, posed.call(), world.has_tree(tree_a), world.has_tree(tree_c), world.has_tree(tree_b)])
		fail += 1
	interaction.step_chop(0.50)
	if not world.has_tree(tree_a) or interaction.chop_cell != tree_a:
		printerr("FAIL chop_sheet_on_single_cut: near tree fell before 0.56 s")
		fail += 1
	interaction.step_chop(0.30)
	if world.has_tree(tree_a) or not world.has_tree(tree_c) or interaction.chop_cell != tree_c:
		printerr("FAIL chop_sheet_on_single_cut: queue did not move to the far tree")
		fail += 1
	interaction.step_chop(0.70)
	if world.has_tree(tree_c) or not world.has_tree(tree_b) or interaction.chopping():
		printerr("FAIL chop_sheet_on_single_cut: far tree %s side tree %s chopping %s"
				% [world.has_tree(tree_c), world.has_tree(tree_b), interaction.chopping()])
		fail += 1
	# A drag toward the remaining side tree plays its sheet and does not fell it yet.
	gesture.call(feet, at.call(Vector2(15.5, 10.5)))
	if not posed.call() or interaction.chop_cell != tree_b or not world.has_tree(tree_b):
		printerr("FAIL chop_sheet_on_single_cut: one-tree drag chopping %s cell %s pose %s frame %s tree %s"
				% [interaction.chopping(), interaction.chop_cell, chop_sprite.visible, chop_sprite.frame_coords, world.has_tree(tree_b)])
		fail += 1
	interaction.step_chop(0.16)
	if not chop_sprite.visible or chop_sprite.frame_coords.x < 1:
		printerr("FAIL chop_sheet_on_single_cut: sheet did not advance (%s %s)"
				% [chop_sprite.visible, chop_sprite.frame_coords])
		fail += 1
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_chop_sheet_on_single_cut")
	return fail


func _test_chop_sweep_bounds_and_cancel() -> int:
	## A tap north selects the facing cone out to CHOP_REACH, not the cell under
	## the finger alone. 240 px is inside and 256 px is outside. Sword reach
	## stays 30. Recovery movement, mode, and death do not start the next tree.
	print("-- test_chop_sweep_bounds_and_cancel")
	var fail := 0
	if AimConeStyle.SWORD_REACH != 30.0 or Interaction.CHOP_REACH != 240.0:
		printerr("FAIL chop_sweep_bounds: reach chop %s sword %s" % [Interaction.CHOP_REACH, AimConeStyle.SWORD_REACH])
		return 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var world = scene.get_node("World/worldMap")
	world.set_process(false)
	world.clear()
	for x in range(-4, 24):
		for y in range(-8, 16):
			world.set_cell(0, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
	var near := Vector2i(10, 8)       # 32 px north
	var mid := Vector2i(10, 6)        # 64 px
	var edge := Vector2i(10, 10 - 15) # 240 px, on the chop boundary
	var past := Vector2i(10, 10 - 16) # 256 px, past it
	var side := Vector2i(16, 10)      # 96 px east, outside a north cone
	for cell in [near, mid, edge, past, side]:
		world.set_cell(1, cell, TileCatalog.SOURCE_ID, TileCatalog.TREE)
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	player.position = world.to_global(world.map_to_local(Vector2i(10, 10)))
	player.lastAnimDirection = "Up"
	scene.get_node("World").add_child(player)
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	interaction.set_process(false)
	interaction.set_mode(Interaction.Mode.INTERACT)
	var inventory: Inventory = scene.get_node("Inventory")
	var vp: Viewport = scene.get_viewport()
	var at := func(cell: Vector2) -> Vector2:
		return interaction.get_canvas_transform() * world.to_global(cell * 16.0)
	var tap := func(pos: Vector2) -> void:
		var press := InputEventScreenTouch.new()
		press.position = pos
		press.pressed = true
		vp.push_input(press, true)
		var lift := InputEventScreenTouch.new()
		lift.position = pos
		lift.pressed = false
		vp.push_input(lift, true)
	# Inside the boundary, outside it, and off to the side.
	if not interaction.chop_in_reach(edge) or interaction.chop_in_reach(past) \
			or player.global_position.distance_to(interaction.cell_center(edge)) > 240.0 \
			or player.global_position.distance_to(interaction.cell_center(past)) <= 240.0 \
			or player.global_position.distance_to(interaction.cell_center(near)) <= AimConeStyle.SWORD_REACH:
		printerr("FAIL chop_sweep_bounds: distances edge %.1f past %.1f near %.1f"
				% [player.global_position.distance_to(interaction.cell_center(edge)),
				player.global_position.distance_to(interaction.cell_center(past)),
				player.global_position.distance_to(interaction.cell_center(near))])
		fail += 1
	tap.call(at.call(Vector2(10.5, 8.5)))
	var selected: Array[Vector2i] = interaction.sweep_cells()
	var want: Array[Vector2i] = [near, mid, edge]
	if selected != want:
		printerr("FAIL chop_sweep_bounds: tap selected %s, want %s" % [selected, want])
		fail += 1
	# Same gesture again does not add a second copy of the near tree.
	tap.call(at.call(Vector2(10.5, 8.5)))
	if interaction.sweep_cells() != want:
		printerr("FAIL chop_sweep_bounds: second tap changed the sweep to %s" % [interaction.sweep_cells()])
		fail += 1
	# Drop the far queued tree before its turn. It must not pay wood.
	world.erase_cell(1, edge)
	var tree_wood := InteractableCatalog.by_id("tree").amount_of(Inventory.WOOD)
	interaction.step_chop(0.60)  # recovery of the first tree, after the fall
	if world.has_tree(near) or interaction.chop_cell != near or not interaction.chopping():
		printerr("FAIL chop_sweep_bounds: first tree not in recovery")
		fail += 1
	player.global_position += Vector2(4, 0)
	interaction.step_chop(0.20)
	if interaction.chopping() or not interaction.sweep_cells().is_empty() or not world.has_tree(mid) \
			or inventory.count_of(Inventory.WOOD) != tree_wood:
		printerr("FAIL chop_sweep_bounds: recovery move started the next tree wood %s chopping %s"
				% [inventory.count_of(Inventory.WOOD), interaction.chopping()])
		fail += 1
	# Mode switch during recovery of a fresh two-tree sweep.
	player.global_position = world.to_global(world.map_to_local(Vector2i(10, 10)))
	world.set_cell(1, near, TileCatalog.SOURCE_ID, TileCatalog.TREE)
	tap.call(at.call(Vector2(10.5, 8.5)))
	interaction.step_chop(0.60)
	interaction.set_mode(Interaction.Mode.COMBAT)
	interaction.step_chop(0.20)
	if interaction.chopping() or world.has_tree(mid) == false or not world.has_tree(side):
		printerr("FAIL chop_sweep_bounds: recovery mode switch did not stop the queue")
		fail += 1
	# Death during recovery.
	interaction.set_mode(Interaction.Mode.INTERACT)
	player.global_position = world.to_global(world.map_to_local(Vector2i(10, 10)))
	world.set_cell(1, near, TileCatalog.SOURCE_ID, TileCatalog.TREE)
	tap.call(at.call(Vector2(10.5, 8.5)))
	interaction.step_chop(0.60)
	player.health.set_health_now(0)
	interaction.step_chop(0.20)
	if interaction.chopping() or not world.has_tree(mid):
		printerr("FAIL chop_sweep_bounds: recovery death started the next tree")
		fail += 1
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_chop_sweep_bounds_and_cancel")
	return fail
