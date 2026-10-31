extends "res://tests/helpers/test_helpers.gd"
## Interact mode: the HUD mode button, cutting plants in reach, and single-player only.


func _test_interact_mode_toggle() -> int:
	## The HUD mode button, the menu button's size and just left of it,
	## switches between combat (the default) and interact mode and shows the
	## current mode's icon.
	print("-- test_interact_mode_toggle")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.add_player(scene.multiplayer.get_unique_id())
	scene.get_node("CanvasLayer1").show()
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	var button: Button = scene.get_node("CanvasLayer1/ModeButton")
	var menu_rect: Rect2 = scene.get_node("CanvasLayer1/InGameMenu").menu_button.get_global_rect()
	if interaction.mode != Interaction.Mode.COMBAT or button.icon != Interaction.ICONS[Interaction.Mode.COMBAT]:
		printerr("FAIL interact_mode_toggle: does not start in combat mode with its icon")
		fail += 1
	var rect := button.get_global_rect()
	if rect.size != menu_rect.size or rect.intersects(menu_rect) or rect.end.x > menu_rect.position.x \
			or not interaction.player.get_node("Camera2D/MapZoom").starts_on_hud(rect.get_center()):
		printerr("FAIL interact_mode_toggle: mode button at %s, menu button at %s" % [rect, menu_rect])
		fail += 1
	button.pressed.emit()
	if interaction.mode != Interaction.Mode.INTERACT or button.icon != Interaction.ICONS[Interaction.Mode.INTERACT] \
			or not button.button_pressed:
		printerr("FAIL interact_mode_toggle: the button did not switch to interact mode")
		fail += 1
	button.pressed.emit()
	if interaction.mode != Interaction.Mode.COMBAT or button.icon != Interaction.ICONS[Interaction.Mode.COMBAT]:
		printerr("FAIL interact_mode_toggle: the button did not switch back to combat mode")
		fail += 1
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_interact_mode_toggle")
	return fail


func _test_interact_cut_trees() -> int:
	## In interact mode a drag across a row of trees and a bush cuts the plants
	## in the range that are within reach of the player, and only those: trees
	## out of reach or outside the range stay. Each cut tree becomes a walkable
	## stump and the bush a BUSH_STUMP, each giving its type's wood, shown on
	## the HUD. A tap chops down the nearest
	## tree next to it, a pinch cuts nothing, and combat mode cuts nothing.
	print("-- test_interact_cut_trees")
	var fail := 0
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var world = scene.get_node("World/worldMap")
	world.clear()
	for x in range(-2, 30):
		for y in range(-2, 20):
			world.set_cell(0, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
	for x in range(4, 21):
		world.set_cell(1, Vector2i(x, 8), TileCatalog.SOURCE_ID, TileCatalog.TREE)
	world.set_cell(1, Vector2i(12, 8), TileCatalog.SOURCE_ID, TileCatalog.BUSH)
	world.set_cell(1, Vector2i(13, 8), TileCatalog.SOURCE_ID, TileCatalog.TREE_PINE_SMALL)
	world.set_cell(1, Vector2i(10, 6), TileCatalog.SOURCE_ID, TileCatalog.TREE)
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	player.position = world.to_global(world.map_to_local(Vector2i(10, 10)))
	scene.get_node("World").add_child(player)
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	var inventory: Inventory = scene.get_node("Inventory")
	var vp: Viewport = scene.get_viewport()
	var at := func(cell: Vector2) -> Vector2:  # cell units (0.5 = centre) to viewport px
		return interaction.get_canvas_transform() * world.to_global(cell * 16.0)
	var touch := func(index: int, pos: Vector2, pressed: bool) -> void:
		var e := InputEventScreenTouch.new()
		e.index = index
		e.position = pos
		e.pressed = pressed
		vp.push_input(e, true)
	var drag := func(index: int, pos: Vector2) -> void:
		var e := InputEventScreenDrag.new()
		e.index = index
		e.position = pos
		vp.push_input(e, true)
	var row := func() -> Array:  # x of the cells in row 8 that still have a tree
		var out := []
		for x in range(4, 21):
			if world.has_tree(Vector2i(x, 8)):
				out.append(x)
		return out
	var swipe := func() -> void:  # drag from the right end of row 8 to x=5
		touch.call(0, at.call(Vector2(16.5, 8.4)), true)
		drag.call(0, at.call(Vector2(11.0, 8.6)))
		drag.call(0, at.call(Vector2(5.5, 8.6)))
		touch.call(0, at.call(Vector2(5.5, 8.6)), false)

	# Combat mode: the same drag cuts nothing.
	swipe.call()
	if row.call().size() != 16 or inventory.count_of(Inventory.WOOD) != 0:
		printerr("FAIL interact_cut_trees: combat mode cut %s" % [row.call()])
		fail += 1
	interaction.set_mode(Interaction.Mode.INTERACT)
	# A pinch is not a selection.
	touch.call(0, at.call(Vector2(16.5, 8.4)), true)
	touch.call(1, at.call(Vector2(6.5, 8.4)), true)
	drag.call(0, at.call(Vector2(5.5, 8.6)))
	touch.call(0, at.call(Vector2(5.5, 8.6)), false)
	touch.call(1, at.call(Vector2(6.5, 8.4)), false)
	if row.call().size() != 16:
		printerr("FAIL interact_cut_trees: a pinch cut %s" % [row.call()])
		fail += 1
	# Reach is 80 px: from (10, 10) that is x 6..14 on row 8 (12 is a bush).
	swipe.call()
	var want_cut := [6, 7, 8, 9, 10, 11, 13, 14]
	var tree_wood := InteractableCatalog.by_id("tree").amount_of(Inventory.WOOD)
	var want_wood := want_cut.size() * tree_wood + InteractableCatalog.by_id("bush").amount_of(Inventory.WOOD)
	var left: Array = row.call()
	for x in want_cut:
		var cell := Vector2i(x, 8)
		if left.has(x) or world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, cell) != TileCatalog.STUMP:
			printerr("FAIL interact_cut_trees: %s is not a stump after the drag" % cell)
			fail += 1
	if left != [4, 5, 15, 16, 17, 18, 19, 20] or world.choppable(Vector2i(12, 8)) != null \
			or world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, Vector2i(12, 8)) != TileCatalog.BUSH_STUMP \
			or not world.has_tree(Vector2i(10, 6)):
		printerr("FAIL interact_cut_trees: trees left after the drag %s" % [left])
		fail += 1
	var hud: ResourceHud = scene.get_node("CanvasLayer1/ResourceHud")
	if inventory.count_of(Inventory.WOOD) != want_wood or hud.label.text != str(want_wood):
		printerr("FAIL interact_cut_trees: wood %s, HUD '%s' after cutting %s trees and a bush, want %s"
				% [inventory.count_of(Inventory.WOOD), hud.label.text, want_cut.size(), want_wood])
		fail += 1
	# Stumps are walkable; an uncut tree still blocks.
	await physics_frame
	await physics_frame
	var body: CollisionShape2D = player.get_node("CollisionShape2D")
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body.shape
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	var space: PhysicsDirectSpaceState2D = world.get_world_2d().direct_space_state
	for x in [8, 17]:
		query.transform = Transform2D(0, world.to_global(world.map_to_local(Vector2i(x, 6))) + body.position)
		query.motion = Vector2(0, 64)
		var passes: bool = space.cast_motion(query)[0] >= 1.0
		if passes != (x == 8):
			printerr("FAIL interact_cut_trees: walking through column %s passes=%s" % [x, passes])
			fail += 1
	# A tap on the empty cell next to the tree at (10, 6) chops it down.
	touch.call(0, at.call(Vector2(11.3, 6.5)), true)
	touch.call(0, at.call(Vector2(11.3, 6.5)), false)
	interaction.step_chop(1.0)
	if world.has_tree(Vector2i(10, 6)) or inventory.count_of(Inventory.WOOD) != want_wood + tree_wood:
		printerr("FAIL interact_cut_trees: the tap did not cut the tree at (10, 6)")
		fail += 1
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_interact_cut_trees")
	return fail


func _test_interact_off_in_multiplayer() -> int:
	## Interact mode is single-player only (cuts are not synced, #223). Alone
	## (offline or hosting with no peer) the mode button shows and a tap cuts.
	## With a peer connected to the host, and on a client, the button is
	## hidden and disabled, the mode is forced to and stays combat, and a tap
	## or a drag cuts nothing.
	print("-- test_interact_off_in_multiplayer")
	var fail := 0
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL interact_off_in_multiplayer found no free UDP port")
		return 1
	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var menu: Node = scene.get_node("CanvasLayer2/MainMenu")
	menu.hide()
	menu.set_process_unhandled_input(false)
	scene.get_node("CanvasLayer1").show()
	var world = scene.get_node("World/worldMap")
	world.clear()
	for x in range(-2, 20):
		for y in range(-2, 20):
			world.set_cell(0, Vector2i(x, y), TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
	for x in range(6, 15):
		world.set_cell(1, Vector2i(x, 8), TileCatalog.SOURCE_ID, TileCatalog.TREE)
	var player = load("res://Player/character_body_2d.tscn").instantiate()
	player.name = str(scene.multiplayer.get_unique_id())
	player.position = world.to_global(world.map_to_local(Vector2i(10, 10)))
	scene.get_node("World").add_child(player)
	await process_frame
	var interaction: Interaction = scene.get_node("World/Interaction")
	var button: Button = scene.get_node("CanvasLayer1/ModeButton")
	var inventory: Inventory = scene.get_node("Inventory")
	var vp: Viewport = scene.get_viewport()
	var at := func(cell: Vector2) -> Vector2:  # cell units (0.5 = centre) to viewport px
		return interaction.get_canvas_transform() * world.to_global(cell * 16.0)
	var touch := func(pos: Vector2, pressed: bool) -> void:
		var e := InputEventScreenTouch.new()
		e.position = pos
		e.pressed = pressed
		vp.push_input(e, true)
	var drag := func(pos: Vector2) -> void:
		var e := InputEventScreenDrag.new()
		e.position = pos
		vp.push_input(e, true)
	var trees := func() -> int:
		var n := 0
		for x in range(6, 15):
			n += int(world.has_tree(Vector2i(x, 8)))
		return n
	var frames := func() -> void:
		for i in 3:
			await process_frame
	# Gated: hidden, disabled, combat even when asked for interact, and map
	# input cuts nothing. Returns the failures.
	var check_gated := func(label: String) -> int:
		var f := 0
		for x in range(6, 15):  # a full row, so a wrong cut shows
			world.set_cell(1, Vector2i(x, 8), TileCatalog.SOURCE_ID, TileCatalog.TREE)
		var before: int = trees.call()
		if button.visible or not button.disabled or interaction.mode != Interaction.Mode.COMBAT:
			printerr("FAIL interact_off_in_multiplayer %s: button visible %s, disabled %s, mode %s"
					% [label, button.visible, button.disabled, interaction.mode])
			f += 1
		button.pressed.emit()
		interaction.toggle_mode()
		interaction.set_mode(Interaction.Mode.INTERACT)
		if interaction.mode != Interaction.Mode.COMBAT:
			printerr("FAIL interact_off_in_multiplayer %s: switched to interact mode" % label)
			f += 1
		touch.call(at.call(Vector2(9.5, 8.5)), true)
		touch.call(at.call(Vector2(9.5, 8.5)), false)
		touch.call(at.call(Vector2(14.5, 8.5)), true)
		drag.call(at.call(Vector2(10.0, 8.6)))
		drag.call(at.call(Vector2(6.5, 8.6)))
		touch.call(at.call(Vector2(6.5, 8.6)), false)
		if trees.call() != before or interaction.cut_range(Rect2(at.call(Vector2(6, 8)), Vector2(160, 16))) != 0:
			printerr("FAIL interact_off_in_multiplayer %s: cut %s trees" % [label, before - trees.call()])
			f += 1
		return f

	# Offline: the button shows and a tap cuts.
	if not button.visible or button.disabled:
		printerr("FAIL interact_off_in_multiplayer offline: button visible %s, disabled %s" % [button.visible, button.disabled])
		fail += 1
	interaction.set_mode(Interaction.Mode.INTERACT)
	touch.call(at.call(Vector2(10.5, 8.5)), true)
	touch.call(at.call(Vector2(10.5, 8.5)), false)
	interaction.step_chop(1.0)
	if world.has_tree(Vector2i(10, 8)) or inventory.count_of(Inventory.WOOD) != InteractableCatalog.by_id("tree").amount_of(Inventory.WOOD):
		printerr("FAIL interact_off_in_multiplayer offline: the tap did not cut (10, 8)")
		fail += 1

	# Host: alone it is still single-player; a joining peer forces combat.
	var smp := SceneMultiplayer.new()
	set_multiplayer(smp, interaction.get_path())
	var speer := ENetMultiplayerPeer.new()
	speer.create_server(port)
	smp.multiplayer_peer = speer
	await frames.call()
	if interaction.mode != Interaction.Mode.INTERACT or not button.visible:
		printerr("FAIL interact_off_in_multiplayer hosting alone: mode %s, button visible %s" % [interaction.mode, button.visible])
		fail += 1
	var client_root := Node.new()
	client_root.name = "InteractClient"
	root.add_child(client_root)
	var cmp := SceneMultiplayer.new()
	set_multiplayer(cmp, client_root.get_path())
	var cpeer := ENetMultiplayerPeer.new()
	cpeer.create_client("127.0.0.1", port)
	cmp.multiplayer_peer = cpeer
	if not await _client_connected(smp, cpeer):
		printerr("FAIL interact_off_in_multiplayer client did not connect to the host")
		fail += 1
	else:
		await frames.call()
		fail += check_gated.call("host with a peer")
	cpeer.close()
	speer.close()
	set_multiplayer(null, client_root.get_path())
	set_multiplayer(null, interaction.get_path())
	await frames.call()
	if not button.visible or button.disabled:
		printerr("FAIL interact_off_in_multiplayer back offline: button visible %s, disabled %s" % [button.visible, button.disabled])
		fail += 1

	# Client: gated while connecting and once connected.
	var port2 := _free_udp_port()
	var smp2 := SceneMultiplayer.new()
	set_multiplayer(smp2, client_root.get_path())
	var speer2 := ENetMultiplayerPeer.new()
	speer2.create_server(port2)
	smp2.multiplayer_peer = speer2
	var cmp2 := SceneMultiplayer.new()
	set_multiplayer(cmp2, interaction.get_path())
	interaction.set_mode(Interaction.Mode.INTERACT)
	var cpeer2 := ENetMultiplayerPeer.new()
	cpeer2.create_client("127.0.0.1", port2)
	cmp2.multiplayer_peer = cpeer2
	await frames.call()
	if interaction.mode != Interaction.Mode.COMBAT or button.visible:
		printerr("FAIL interact_off_in_multiplayer connecting client: mode %s, button visible %s" % [interaction.mode, button.visible])
		fail += 1
	if not await _client_connected(smp2, cpeer2):
		printerr("FAIL interact_off_in_multiplayer client did not connect")
		fail += 1
	else:
		await frames.call()
		fail += check_gated.call("client")
	cpeer2.close()
	speer2.close()
	set_multiplayer(null, interaction.get_path())
	set_multiplayer(null, client_root.get_path())
	client_root.queue_free()
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_interact_off_in_multiplayer")
	return fail
