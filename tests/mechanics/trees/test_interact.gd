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
	## In interact mode a drag aims a chop cone. Plants in that cone are queued
	## and each plays a full chop. Plants outside the cone stay. Each cut tree
	## becomes a walkable stump and the bush a BUSH_STUMP, each giving its
	## type's wood, shown on the HUD. A tap chops the nearest tree next to it,
	## a pinch cuts nothing, and combat mode cuts nothing.
	print("-- test_interact_cut_trees")
	var fail := 0
	if AimConeStyle.SWORD_REACH != 30.0 or Interaction.CHOP_REACH / AimConeStyle.SWORD_REACH < 4.0:
		printerr("FAIL interact_cut_trees: chop reach %s sword reach %s"
				% [Interaction.CHOP_REACH, AimConeStyle.SWORD_REACH])
		fail += 1
	print("chop reach %s px, sword reach %s px, ratio %.2f" % [
			Interaction.CHOP_REACH, AimConeStyle.SWORD_REACH,
			Interaction.CHOP_REACH / AimConeStyle.SWORD_REACH])
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
	var swipe := func() -> void:  # aim up from the hero, 50 world px (short of the far trees)
		touch.call(0, at.call(Vector2(10.5, 10.5)), true)
		drag.call(0, at.call(Vector2(10.5, 10.5 - 50.0 / 16.0)))
		touch.call(0, at.call(Vector2(10.5, 10.5 - 50.0 / 16.0)), false)

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
	# Cone aimed up, 50 px. The near row is inside. The ends and (10, 6) are not.
	# Nothing is a stump until each queued chop finishes.
	swipe.call()
	if not interaction.chopping() or inventory.count_of(Inventory.WOOD) != 0:
		printerr("FAIL interact_cut_trees: drag did not queue a chop (chopping %s wood %s)"
				% [interaction.chopping(), inventory.count_of(Inventory.WOOD)])
		fail += 1
	var tree_wood := InteractableCatalog.by_id("tree").amount_of(Inventory.WOOD)
	var want_cut := [8, 9, 10, 11]
	for _step in 8:
		interaction.step_chop(0.70)
	var want_wood := want_cut.size() * tree_wood + InteractableCatalog.by_id("bush").amount_of(Inventory.WOOD)
	var left: Array = row.call()
	for x in want_cut:
		var cell := Vector2i(x, 8)
		if left.has(x) or world.get_cell_atlas_coords(world.GROUND_DECOR_LAYER, cell) != TileCatalog.STUMP:
			printerr("FAIL interact_cut_trees: %s is not a stump after the queue" % cell)
			fail += 1
	if left.has(8) or left.has(9) or left.has(10) or left.has(11) \
			or not left.has(6) or not left.has(14) \
			or world.choppable(Vector2i(12, 8)) != null \
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
	# A tap north is one sweep in that direction, not a second chop of the same cell.
	var far_east := Vector2i(10 + 20, 10)
	world.set_cell(0, far_east, TileCatalog.SOURCE_ID, TileCatalog.GRASS_A)
	world.set_cell(1, far_east, TileCatalog.SOURCE_ID, TileCatalog.TREE)
	touch.call(0, at.call(Vector2(10.5, 6.5)), true)
	touch.call(0, at.call(Vector2(10.5, 6.5)), false)
	var tapped: Array[Vector2i] = interaction.sweep_cells()
	if tapped.is_empty() or not Vector2i(10, 6) in tapped or far_east in tapped:
		printerr("FAIL interact_cut_trees: tap sweep %s" % [tapped])
		fail += 1
	var tap_wood := 0
	for cell in tapped:
		var kind: InteractableType = world.choppable(cell)
		if kind != null:
			tap_wood += kind.amount_of(Inventory.WOOD)
	for _i in tapped.size():
		interaction.step_chop(0.70)
	if interaction.chopping() or not interaction.sweep_cells().is_empty() \
			or world.has_tree(Vector2i(10, 6)) or not world.has_tree(far_east) \
			or inventory.count_of(Inventory.WOOD) != want_wood + tap_wood:
		printerr("FAIL interact_cut_trees: tap sweep wood %s want %s chopping %s"
				% [inventory.count_of(Inventory.WOOD), want_wood + tap_wood, interaction.chopping()])
		fail += 1
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_interact_cut_trees")
	return fail


func _test_interact_in_multiplayer() -> int:
	## Interact mode works in every session state (#223): offline a tap cuts,
	## and hosting alone, hosting with a peer, connecting and connected as a
	## client the mode button shows, is enabled and interact mode stays on.
	## The cuts themselves go through the host there; test_cut_sync_two_players
	## (tests/net/test_cut_sync.gd) plays those across real processes.
	print("-- test_interact_in_multiplayer")
	var fail := 0
	var port := _free_udp_port()
	if port == 0:
		printerr("FAIL interact_in_multiplayer found no free UDP port")
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
	var frames := func() -> void:
		for i in 3:
			await process_frame
	# Open: the button shows and is enabled, and interact mode is kept.
	var check_open := func(label: String) -> int:
		interaction.set_mode(Interaction.Mode.INTERACT)
		await frames.call()
		if not button.visible or button.disabled or interaction.mode != Interaction.Mode.INTERACT:
			printerr("FAIL interact_in_multiplayer %s: button visible %s, disabled %s, mode %s"
					% [label, button.visible, button.disabled, interaction.mode])
			return 1
		return 0

	# Offline: the button shows and a tap cuts.
	if not button.visible or button.disabled:
		printerr("FAIL interact_in_multiplayer offline: button visible %s, disabled %s" % [button.visible, button.disabled])
		fail += 1
	interaction.set_mode(Interaction.Mode.INTERACT)
	touch.call(at.call(Vector2(10.5, 8.5)), true)
	touch.call(at.call(Vector2(10.5, 8.5)), false)
	interaction.step_chop(1.0)
	if world.has_tree(Vector2i(10, 8)) or inventory.count_of(Inventory.WOOD) != InteractableCatalog.by_id("tree").amount_of(Inventory.WOOD):
		printerr("FAIL interact_in_multiplayer offline: the tap did not cut (10, 8)")
		fail += 1

	# Host: alone, then with a peer.
	var smp := SceneMultiplayer.new()
	set_multiplayer(smp, interaction.get_path())
	var speer := ENetMultiplayerPeer.new()
	speer.create_server(port)
	smp.multiplayer_peer = speer
	fail += await check_open.call("hosting alone")
	var client_root := Node.new()
	client_root.name = "InteractClient"
	root.add_child(client_root)
	var cmp := SceneMultiplayer.new()
	set_multiplayer(cmp, client_root.get_path())
	var cpeer := ENetMultiplayerPeer.new()
	cpeer.create_client("127.0.0.1", port)
	cmp.multiplayer_peer = cpeer
	if not await _client_connected(smp, cpeer):
		printerr("FAIL interact_in_multiplayer client did not connect to the host")
		fail += 1
	else:
		await frames.call()
		fail += await check_open.call("host with a peer")
	cpeer.close()
	speer.close()
	set_multiplayer(null, client_root.get_path())
	set_multiplayer(null, interaction.get_path())
	fail += await check_open.call("back offline")

	# Client: while connecting and once connected.
	var port2 := _free_udp_port()
	var smp2 := SceneMultiplayer.new()
	set_multiplayer(smp2, client_root.get_path())
	var speer2 := ENetMultiplayerPeer.new()
	speer2.create_server(port2)
	smp2.multiplayer_peer = speer2
	var cmp2 := SceneMultiplayer.new()
	set_multiplayer(cmp2, interaction.get_path())
	var cpeer2 := ENetMultiplayerPeer.new()
	cpeer2.create_client("127.0.0.1", port2)
	cmp2.multiplayer_peer = cpeer2
	fail += await check_open.call("connecting client")
	if not await _client_connected(smp2, cpeer2):
		printerr("FAIL interact_in_multiplayer client did not connect")
		fail += 1
	else:
		await frames.call()
		fail += await check_open.call("client")
	cpeer2.close()
	speer2.close()
	set_multiplayer(null, interaction.get_path())
	set_multiplayer(null, client_root.get_path())
	client_root.queue_free()
	player.queue_free()
	scene.queue_free()
	await process_frame
	if fail == 0:
		print("PASS test_interact_in_multiplayer")
	return fail
